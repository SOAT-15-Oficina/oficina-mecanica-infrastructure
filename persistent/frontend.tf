# Bucket do painel. PRIVADO: acessivel somente pelo CloudFront via Origin Access
# Control. Nada de website hosting -- ele exigiria bucket publico, que
# contornaria o CloudFront.
resource "aws_s3_bucket" "frontend" {
  bucket        = "${local.name}-frontend"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${local.name}-frontend-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_iam_policy_document" "frontend_bucket" {
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.frontend.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.site.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = data.aws_iam_policy_document.frontend_bucket.json
}

# O painel chama /api/customers, mas o monolito serve /customers e a Lambda
# serve /auth/login. Esta funcao remove o prefixo antes de repassar a origem --
# e o que permite que a API nao precise saber que existe um /api na frente.
resource "aws_cloudfront_function" "strip_api_prefix" {
  name    = "${local.name}-strip-api-prefix"
  runtime = "cloudfront-js-2.0"
  comment = "Remove o prefixo /api antes de encaminhar ao API Gateway"
  publish = true

  code = <<-JS
    function handler(event) {
      var request = event.request;
      if (request.uri.startsWith('/api/')) {
        request.uri = request.uri.substring(4);
      } else if (request.uri === '/api') {
        request.uri = '/';
      }
      return request;
    }
  JS
}

data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

# Repassa tudo do viewer menos o Host -- inclusive o Authorization, sem o qual
# nenhuma rota protegida funcionaria.
data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

# Duas origens numa distribuicao: painel e API na MESMA origem para o browser.
# Isso elimina CORS, dispensa injetar a URL da API no build do front e da uma
# unica URL publica -- que tambem e a base dos links de aprovacao enviados por
# e-mail ao cliente.
resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  comment             = "${local.name} - painel + API"
  default_root_object = "index.html"
  price_class         = "PriceClass_100"

  origin {
    origin_id                = "s3-frontend"
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  origin {
    origin_id   = "api-gateway"
    domain_name = "${aws_apigatewayv2_api.main.id}.execute-api.${var.region}.amazonaws.com"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "s3-frontend"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.optimized.id
    compress               = true
  }

  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "api-gateway"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]

    # Resposta de API nao pode ser cacheada, e o Authorization precisa chegar
    # inteiro na origem.
    cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
    compress                 = true

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.strip_api_prefix.arn
    }
  }

  # Enquanto o ambiente esta desligado (tear-down), o painel continua no ar e a
  # API responde 404. Devolver a pagina de login mascararia isso.
  # NAO adicione custom_error_response aqui.
  #
  # Ele e configurado por DISTRIBUICAO, nao por cache behavior -- e esta
  # distribuicao serve o painel estatico E a API (/api/*). Uma regra
  # "403 -> /index.html" reescreveria tambem as negacoes de RBAC do monolito
  # (internal/routes/middlewares/auth.go), entregando ao navegador um 404 com
  # HTML no lugar do 403 com JSON, cacheado por 10s.
  #
  # Trocar o codigo nao resolve: a API usa 403, 404, 400 e 500 com significado
  # proprio. Qualquer codigo que o site quisesse embelezar colidiria com a API.
  #
  # O custo de nao ter a regra e cosmetico: uma URL inexistente devolve o
  # AccessDenied do S3 em vez do painel. As paginas sao arquivos reais
  # (index.html, board.html, ...), nao ha roteamento client-side para acomodar.

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
