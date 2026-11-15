resource "datadog_dashboard" "saga" {
  count = local.datadog_enabled ? 1 : 0

  title       = "${local.dd_dashboard_prefix} Saga"
  description = "Andamento da Saga da OS: eventos por tipo, filas de entrada e DLQs. Definido em platform/datadog_dashboard_saga.tf."
  layout_type = "ordered"
  reflow_type = "auto"

  template_variable {
    name    = "env"
    prefix  = "env"
    default = var.environment
  }

  widget {
    note_definition {
      content          = "Os eventos vem da metrica de log `oficina.saga_event` (`@event:saga.*`), e as filas das metricas do SQS pela integracao AWS. Fluxo e compensacoes descritos na RFC-0006."
      background_color = "blue"
      font_size        = "14"
      text_align       = "left"
      has_padding      = true
      show_tick        = false
    }
  }

  widget {
    group_definition {
      title       = "Sagas"
      layout_type = "ordered"

      widget {
        timeseries_definition {
          title       = "Eventos da Saga por tipo"
          show_legend = true

          request {
            q            = "sum:oficina.saga_event{$env} by {event}.as_count()"
            display_type = "bars"
          }
        }
      }

      widget {
        toplist_definition {
          title = "Eventos da Saga nas ultimas 24h"

          request {
            q = "top(sum:oficina.saga_event{$env} by {event}.as_count(), 10, 'sum', 'desc')"
          }
        }
      }
    }
  }

  widget {
    group_definition {
      title       = "Filas"
      layout_type = "ordered"

      widget {
        timeseries_definition {
          title       = "Mensagens visiveis nas inbox"
          show_legend = true

          request {
            q            = "max:aws.sqs.approximate_number_of_messages_visible{queuename:${local.dd_queue_prefix}-*-inbox.fifo} by {queuename}"
            display_type = "line"
          }
        }
      }

      widget {
        timeseries_definition {
          title       = "Idade da mensagem mais antiga nas inbox"
          show_legend = true

          request {
            q            = "max:aws.sqs.approximate_age_of_oldest_message{queuename:${local.dd_queue_prefix}-*-inbox.fifo} by {queuename}"
            display_type = "line"
          }

          yaxis {
            label = "segundos"
          }

          marker {
            display_type = "error dashed"
            value        = "y = 300"
            label        = "limiar do alerta"
          }
        }
      }

      widget {
        query_value_definition {
          title     = "Mensagens em DLQ"
          precision = 0

          request {
            aggregator = "last"
            q          = "sum:aws.sqs.approximate_number_of_messages_visible{queuename:${local.dd_queue_prefix}-*-inbox-dlq.fifo}"

            conditional_formats {
              comparator = ">"
              value      = 0
              palette    = "white_on_red"
            }

            conditional_formats {
              comparator = "<="
              value      = 0
              palette    = "white_on_green"
            }
          }
        }
      }

      widget {
        timeseries_definition {
          title       = "Profundidade das DLQs"
          show_legend = true

          request {
            q            = "max:aws.sqs.approximate_number_of_messages_visible{queuename:${local.dd_queue_prefix}-*-inbox-dlq.fifo} by {queuename}"
            display_type = "bars"
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
          title   = "Eventos recentes da Saga"
          query   = "env:${var.environment} @event:saga.*"
          columns = ["service", "@event", "@saga_id", "@work_order_id", "@message_type"]

          sort {
            column = "time"
            order  = "desc"
          }
        }
      }
    }
  }
}
