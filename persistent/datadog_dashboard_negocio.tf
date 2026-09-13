resource "datadog_dashboard" "business" {
  count = local.datadog_enabled ? 1 : 0

  title       = "${local.dd_dashboard_prefix} Negocio"
  description = "Volume de ordens de servico, tempo por status e falhas de integracao. Definido em persistent/datadog_dashboard_negocio.tf."
  layout_type = "ordered"
  reflow_type = "auto"

  template_variable {
    name    = "env"
    prefix  = "env"
    default = var.environment
  }

  widget {
    note_definition {
      content          = "Todos os numeros abaixo vem de METRICAS DE LOG (persistent/datadog_metrics.tf), contadas a partir dos eventos de dominio do `slog` (ADR-0011). O volume diario e conferivel contra o banco: `SELECT date(received_at), COUNT(*) FROM work_orders GROUP BY 1`."
      background_color = "blue"
      font_size        = "14"
      text_align       = "left"
      has_padding      = true
      show_tick        = false
    }
  }

  widget {
    group_definition {
      title       = "Volume de ordens de servico"
      layout_type = "ordered"

      widget {
        query_value_definition {
          title     = "Ordens abertas nas ultimas 24h"
          precision = 0
          live_span = "1d"

          request {
            aggregator = "sum"
            q          = "sum:oficina.work_order_created{$env}.as_count()"
          }
        }
      }

      widget {
        timeseries_definition {
          title       = "Volume diario de ordens de servico"
          show_legend = true
          live_span   = "1w"

          request {
            q            = "sum:oficina.work_order_created{$env}.as_count()"
            display_type = "bars"

            style {
              palette = "cool"
            }
          }

          yaxis {
            include_zero = true
          }
        }
      }

      widget {
        timeseries_definition {
          title       = "Transicoes de status aceitas, por status de destino"
          show_legend = true

          request {
            q            = "sum:oficina.work_order_status_changed{$env} by {to}.as_count()"
            display_type = "bars"
          }
        }
      }
    }
  }

  widget {
    group_definition {
      title       = "Tempo medio de execucao por status"
      layout_type = "ordered"

      widget {
        note_definition {
          content          = "`@duration_ms` e quanto a ordem passou no status ANTERIOR; o agrupamento por `to` le-se como 'tempo ate sair de cada etapa'. Diagnostico, Execucao e Finalizacao aparecem como valores da tag `to`."
          background_color = "gray"
          font_size        = "12"
          text_align       = "left"
          has_padding      = true
          show_tick        = false
        }
      }

      widget {
        toplist_definition {
          title = "Tempo medio por status"

          request {
            q = "avg:oficina.work_order_stage_duration{$env} by {to}"
          }
        }
      }

      widget {
        timeseries_definition {
          title       = "Tempo medio por status ao longo do tempo"
          show_legend = true

          request {
            q            = "avg:oficina.work_order_stage_duration{$env} by {to}"
            display_type = "line"
          }

          yaxis {
            label = "ms"
          }
        }
      }

      widget {
        timeseries_definition {
          title       = "Cauda: p95 por status"
          description = "A media esconde a ordem esquecida. E o p95 que a mostra."
          show_legend = true

          request {
            q            = "p95:oficina.work_order_stage_duration{$env} by {to}"
            display_type = "line"
          }

          yaxis {
            label = "ms"
          }
        }
      }
    }
  }

  widget {
    group_definition {
      title       = "Erros e falhas nas integracoes"
      layout_type = "ordered"

      widget {
        timeseries_definition {
          title       = "Falhas por integracao"
          show_legend = true

          request {
            q            = "sum:oficina.integration_error{$env} by {integration}.as_count()"
            display_type = "bars"

            style {
              palette = "warm"
            }
          }
        }
      }

      widget {
        timeseries_definition {
          title       = "Orcamentos: enviados x falhos"
          show_legend = true

          request {
            q            = "sum:oficina.budget_sent{$env}.as_count()"
            display_type = "bars"
          }

          request {
            q            = "sum:oficina.budget_send_failed{$env}.as_count()"
            display_type = "bars"

            style {
              palette = "warm"
            }
          }
        }
      }

      widget {
        timeseries_definition {
          title       = "Erros nas dependencias de nuvem"
          description = "5xx do gateway, erros da Lambda e bounces do SES -- as tres integracoes que ficam fora do processo da API."
          show_legend = true

          request {
            q            = "sum:aws.apigateway.5xx{apiid:${local.dd_api_id}}.as_count()"
            display_type = "bars"
          }

          request {
            q            = "sum:aws.lambda.errors{functionname:${local.dd_lambda_name}}.as_count()"
            display_type = "bars"
          }

          request {
            q            = "sum:aws.ses.bounce{$env}.as_count()"
            display_type = "bars"
          }
        }
      }

      widget {
        timeseries_definition {
          title       = "Transicoes recusadas e logins recusados"
          description = "Nem todo numero aqui e defeito: transicao recusada tambem e regra de negocio funcionando. E o SALTO que interessa."
          show_legend = true

          request {
            q            = "sum:oficina.work_order_transition_rejected{$env}.as_count()"
            display_type = "bars"
          }

          request {
            q            = "sum:oficina.auth_login_failed{$env}.as_count()"
            display_type = "bars"
          }
        }
      }

      widget {
        log_stream_definition {
          title   = "Ultimas falhas de integracao"
          query   = "env:${var.environment} status:error @integration:*"
          columns = ["service", "@integration", "@request_id", "@work_order_id", "@error"]

          sort {
            column = "time"
            order  = "desc"
          }
        }
      }
    }
  }
}
