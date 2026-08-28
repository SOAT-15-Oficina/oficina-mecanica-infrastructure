# Placeholder: substituido pelo primeiro deploy do oficina-mecanica-serverless.
# Existe apenas para a funcao poder ser criada -- aws_lambda_function exige um
# artefato de codigo.
def handler(event, context):
    return {
        "statusCode": 503,
        "headers": {"Content-Type": "application/json"},
        "body": '{"error":"funcao ainda nao publicada pelo pipeline do -serverless"}',
    }
