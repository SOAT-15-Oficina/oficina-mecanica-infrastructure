resource "datadog_dashboard" "operational" {
  count = local.datadog_enabled ? 1 : 0

  title       = "${local.dd_dashboard_prefix} Operacional"
  description = "Latencia, recursos do cluster, healthcheck e uptime. Definido em persistent/datadog_dashboard_operacional.tf."
  layout_type = "ordered"
  reflow_type = "auto"
  tags        = local.dd_tags

  template_variable {
    name    = "env"
    prefix  = "env"
    default = var.environment
  }

  widget {
    group_definition {
      title       = "Disponibilidade e borda"
      layout_type = "ordered"

      widget {
        query_value_definition {
          title     = "Uptime de /api/ping (visto de fora)"
          precision = 2
          autoscale = false

          request {
            aggregator = "avg"
            q          = "(sum:synthetics.test_runs{check:api-ping,$env,result:passed}.as_count() / sum:synthetics.test_runs{check:api-ping,$env}.as_count()) * 100"

            conditional_formats {
              comparator = "<"
              value      = 99
              palette    = "white_on_red"
            }

            conditional_formats {
              comparator = ">="
              value      = 99
              palette    = "white_on_green"
            }
          }
        }
      }

      widget {
        timeseries_definition {
          title       = "Tempo de resposta do teste sintetico"
          show_legend = true

          request {
            q            = "avg:synthetics.http.response.time{check:api-ping,$env}"
            display_type = "line"
          }
        }
      }

      widget {
        timeseries_definition {
          title       = "Latencia do API Gateway"
          show_legend = true

          request {
            q            = "avg:aws.apigateway.latency{apiid:${local.dd_api_id}}"
            display_type = "line"
          }

          request {
            q            = "max:aws.apigateway.latency.maximum{apiid:${local.dd_api_id}}"
            display_type = "line"
          }

          yaxis {
            label = "ms"
          }

          marker {
            display_type = "warning dashed"
            value        = "y = 1000"
            label        = "limiar do alerta"
          }
        }
      }

      widget {
        timeseries_definition {
          title       = "Respostas do API Gateway por classe"
          show_legend = true

          request {
            q            = "sum:aws.apigateway.count{apiid:${local.dd_api_id}}.as_count()"
            display_type = "bars"
          }

          request {
            q            = "sum:aws.apigateway.4xx{apiid:${local.dd_api_id}}.as_count()"
            display_type = "bars"
          }

          request {
            q            = "sum:aws.apigateway.5xx{apiid:${local.dd_api_id}}.as_count()"
            display_type = "bars"
          }
        }
      }
    }
  }

  widget {
    group_definition {
      title       = "API (monolito)"
      layout_type = "ordered"

      widget {
        note_definition {
          content          = "Estes paineis saem da METRICA DE LOG `oficina.http_request_duration`, alimentada pela linha de acesso do middleware (ADR-0011). Funcionam com log estruturado apenas -- nao dependem de APM."
          background_color = "blue"
          font_size        = "14"
          text_align       = "left"
          has_padding      = true
          show_tick        = false
        }
      }

      widget {
        timeseries_definition {
          title       = "Latencia da API -- p50, p95 e p99"
          show_legend = true

          request {
            q            = "p50:oficina.http_request_duration{$env,service:monolith}"
            display_type = "line"
          }

          request {
            q            = "p95:oficina.http_request_duration{$env,service:monolith}"
            display_type = "line"
          }

          request {
            q            = "p99:oficina.http_request_duration{$env,service:monolith}"
            display_type = "line"
          }

          yaxis {
            label = "ms"
          }

          marker {
            display_type = "warning dashed"
            value        = "y = 1000"
            label        = "limiar do alerta (p95)"
          }
        }
      }

      widget {
        toplist_definition {
          title = "Rotas mais lentas (p95)"

          request {
            q = "top(p95:oficina.http_request_duration{$env,service:monolith} by {route}, 10, 'mean', 'desc')"
          }
        }
      }

      widget {
        timeseries_definition {
          title       = "Requisicoes por classe de status"
          show_legend = true

          request {
            q            = "count:oficina.http_request_duration{$env,service:monolith,status:2*}.as_count()"
            display_type = "bars"
          }

          request {
            q            = "count:oficina.http_request_duration{$env,service:monolith,status:4*}.as_count()"
            display_type = "bars"
          }

          request {
            q            = "count:oficina.http_request_duration{$env,service:monolith,status:5*}.as_count()"
            display_type = "bars"
          }
        }
      }

      widget {
        query_value_definition {
          title     = "Taxa de erro 5xx (%)"
          precision = 2
          live_span = "4h"

          request {
            aggregator = "avg"
            q          = "(count:oficina.http_request_duration{$env,service:monolith,status:5*}.as_count() / count:oficina.http_request_duration{$env,service:monolith}.as_count()) * 100"

            conditional_formats {
              comparator = ">"
              value      = 1
              palette    = "white_on_red"
            }

            conditional_formats {
              comparator = "<="
              value      = 1
              palette    = "white_on_green"
            }
          }
        }
      }
    }
  }

  widget {
    group_definition {
      title       = "Kubernetes"
      layout_type = "ordered"

      widget {
        timeseries_definition {
          title       = "CPU por pod, contra o limite"
          show_legend = true

          request {
            q            = "avg:kubernetes.cpu.usage.total{$env,kube_namespace:${local.dd_kube_namespace}} by {pod_name} / 1000000000"
            display_type = "area"
          }

          request {
            q            = "avg:kubernetes.cpu.limits{$env,kube_namespace:${local.dd_kube_namespace}} by {pod_name}"
            display_type = "line"
          }

          yaxis {
            label        = "cores"
            include_zero = true
          }
        }
      }

      widget {
        timeseries_definition {
          title       = "Memoria por pod, contra o limite"
          show_legend = true

          request {
            q            = "avg:kubernetes.memory.usage{$env,kube_namespace:${local.dd_kube_namespace}} by {pod_name}"
            display_type = "area"
          }

          request {
            q            = "avg:kubernetes.memory.limits{$env,kube_namespace:${local.dd_kube_namespace}} by {pod_name}"
            display_type = "line"
          }

          yaxis {
            label        = "bytes"
            include_zero = true
          }
        }
      }

      widget {
        timeseries_definition {
          title       = "HPA -- replicas atuais, desejadas e teto"
          show_legend = true

          request {
            q            = "max:kubernetes_state.hpa.current_replicas{$env,kube_namespace:${local.dd_kube_namespace}}"
            display_type = "line"
          }

          request {
            q            = "max:kubernetes_state.hpa.desired_replicas{$env,kube_namespace:${local.dd_kube_namespace}}"
            display_type = "line"
          }

          request {
            q            = "max:kubernetes_state.hpa.max_replicas{$env,kube_namespace:${local.dd_kube_namespace}}"
            display_type = "line"
          }

          yaxis {
            include_zero = true
          }
        }
      }

      widget {
        timeseries_definition {
          title       = "Pods por fase"
          show_legend = true

          request {
            q            = "sum:kubernetes_state.pod.status_phase{$env,kube_namespace:${local.dd_kube_namespace}} by {phase}"
            display_type = "bars"
          }
        }
      }

      widget {
        toplist_definition {
          title       = "Reinicios de container"
          description = "Contador acumulado do kube-state-metrics. Degrau na lista = CrashLoopBackOff."

          request {
            q = "top(max:kubernetes_state.container.restarts{$env,kube_namespace:${local.dd_kube_namespace}} by {pod_name}, 10, 'max', 'desc')"
          }
        }
      }
    }
  }

  widget {
    group_definition {
      title       = "Lambda de autenticacao"
      layout_type = "ordered"

      widget {
        timeseries_definition {
          title       = "Duracao"
          show_legend = true

          request {
            q            = "avg:aws.lambda.duration{functionname:${local.dd_lambda_name}}"
            display_type = "line"
          }

          request {
            q            = "max:aws.lambda.duration.maximum{functionname:${local.dd_lambda_name}}"
            display_type = "line"
          }

          yaxis {
            label = "ms"
          }
        }
      }

      widget {
        timeseries_definition {
          title       = "Invocacoes e erros"
          show_legend = true

          request {
            q            = "sum:aws.lambda.invocations{functionname:${local.dd_lambda_name}}.as_count()"
            display_type = "bars"
          }

          request {
            q            = "sum:aws.lambda.errors{functionname:${local.dd_lambda_name}}.as_count()"
            display_type = "bars"
          }
        }
      }
    }
  }

  widget {
    group_definition {
      title       = "Banco de dados (RDS)"
      layout_type = "ordered"

      widget {
        timeseries_definition {
          title       = "Conexoes"
          show_legend = true

          request {
            q            = "avg:aws.rds.database_connections{dbinstanceidentifier:${local.dd_rds_identifier}}"
            display_type = "line"
          }

          marker {
            display_type = "warning dashed"
            value        = "y = ${floor(var.database_max_connections * 0.8)}"
            label        = "80% de max_connections"
          }
        }
      }

      widget {
        timeseries_definition {
          title       = "CPU"
          show_legend = true

          request {
            q            = "avg:aws.rds.cpuutilization{dbinstanceidentifier:${local.dd_rds_identifier}}"
            display_type = "line"
          }

          yaxis {
            label = "%"
            min   = "0"
            max   = "100"
          }
        }
      }

      widget {
        timeseries_definition {
          title       = "IOPS"
          show_legend = true

          request {
            q            = "avg:aws.rds.read_iops{dbinstanceidentifier:${local.dd_rds_identifier}}"
            display_type = "line"
          }

          request {
            q            = "avg:aws.rds.write_iops{dbinstanceidentifier:${local.dd_rds_identifier}}"
            display_type = "line"
          }
        }
      }

      widget {
        timeseries_definition {
          title       = "Espaco livre"
          show_legend = true

          request {
            q            = "avg:aws.rds.free_storage_space{dbinstanceidentifier:${local.dd_rds_identifier}}"
            display_type = "area"
          }

          yaxis {
            label = "bytes"
          }

          marker {
            display_type = "error dashed"
            value        = "y = ${var.database_free_storage_alert_bytes}"
            label        = "limiar do alerta"
          }
        }
      }
    }
  }

  widget {
    group_definition {
      title       = "Logs"
      layout_type = "ordered"

      widget {
        log_stream_definition {
          title   = "Erros recentes (todos os servicos)"
          query   = "env:${var.environment} status:error"
          columns = ["service", "@request_id", "@route", "@status", "@error"]

          sort {
            column = "time"
            order  = "desc"
          }
        }
      }
    }
  }
}

