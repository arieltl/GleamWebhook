import app/database
import app/web.{type Context, type PaymentWebhook, PaymentWebhook}
import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/io
import gleam/json
import gleam/result
import gleam/string
import gleam/string_tree
import wisp.{type Request, type Response}

fn decode_payment_webhook() -> decode.Decoder(PaymentWebhook) {
  use transaction_id <- decode.field("transaction_id", decode.string)
  use amount <- decode.field("amount", decode.string)
  use currency <- decode.field("currency", decode.string)
  use event <- decode.field("event", decode.string)
  use timestamp <- decode.field("timestamp", decode.string)
  decode.success(PaymentWebhook(
    transaction_id,
    amount,
    currency,
    event,
    timestamp,
  ))
}

fn decode_transaction_id() -> decode.Decoder(String) {
  use transaction_id <- decode.field("transaction_id", decode.string)
  decode.success(transaction_id)
}

fn validate_payment_data(payment: PaymentWebhook) -> Result(Nil, WebhookError) {
  // Check if timestamp is empty or invalid (field missing)
  use _ <- result.try(case payment.timestamp {
    "" -> {
      io.println("Invalid date: timestamp field is empty")
      Error(InvalidPaymentData)
    }
    _ -> Ok(Nil)
  })

  // Additional date format validation (basic check)
  use _ <- result.try(case string.length(payment.timestamp) < 10 {
    True -> {
      io.println(
        "Invalid date format: timestamp too short - " <> payment.timestamp,
      )
      Error(InvalidPaymentData)
    }
    False -> Ok(Nil)
  })

  Ok(Nil)
}

type WebhookError {
  DecodeError(List(decode.DecodeError))
  HttpError(httpc.HttpError)
  PaymentIdMismatch
  InvalidPaymentData
  InvalidToken
}

/// The HTTP request handler- your application!
/// 
pub fn handle_request(req: Request, ctx: Context) -> Response {
  // First, verify the webhook token in the header
  case request.get_header(req, "x-webhook-token") {
    Ok(token) if token == ctx.webhook_token -> {
      // Token is valid, proceed with processing
      process_webhook(req, ctx)
    }
    _ -> {
      // Invalid or missing token
      io.println("Invalid or missing webhook token")
      let body = string_tree.from_string("<h1>Unauthorized</h1>")
      wisp.html_response(body, 400)
    }
  }
}

fn process_webhook(req: Request, ctx: Context) -> Response {
  use json <- wisp.require_json(req)

  let result = {
    use payment_webhook <- result.try(
      decode.run(json, decode_payment_webhook())
      |> result.map_error(DecodeError),
    )

    // Check if the transaction_id exists in the database
    use stored_payment <- result.try(
      database.get_payment_by_id(ctx.db_conn, payment_webhook.transaction_id)
      |> result.map_error(fn(_) { PaymentIdMismatch }),
    )

    // Validate payment data matches stored data exactly
    use _ <- result.try(case stored_payment.amount == payment_webhook.amount {
      False -> {
        io.println(
          "Amount mismatch: stored="
          <> stored_payment.amount
          <> " vs webhook="
          <> payment_webhook.amount,
        )
        Error(InvalidPaymentData)
      }
      True -> Ok(Nil)
    })

    use _ <- result.try(
      case stored_payment.currency == payment_webhook.currency {
        False -> {
          io.println(
            "Currency mismatch: stored="
            <> stored_payment.currency
            <> " vs webhook="
            <> payment_webhook.currency,
          )
          Error(InvalidPaymentData)
        }
        True -> Ok(Nil)
      },
    )

    use _ <- result.try(
      case stored_payment.timestamp == payment_webhook.timestamp {
        False -> {
          io.println(
            "Date/timestamp mismatch: stored="
            <> stored_payment.timestamp
            <> " vs webhook="
            <> payment_webhook.timestamp,
          )
          Error(InvalidPaymentData)
        }
        True -> Ok(Nil)
      },
    )

    use _ <- result.try(case stored_payment.event == payment_webhook.event {
      False -> {
        io.println(
          "Event mismatch: stored="
          <> stored_payment.event
          <> " vs webhook="
          <> payment_webhook.event,
        )
        Error(InvalidPaymentData)
      }
      True -> Ok(Nil)
    })

    // Additional validation for business rules (amount, timestamp, etc.)
    use _ <- result.try(validate_payment_data(payment_webhook))

    let payload =
      json.object([
        #("transaction_id", json.string(payment_webhook.transaction_id)),
      ])

    let assert Ok(confirm_request) =
      request.to("http://localhost:5001/confirmar")
    let req =
      confirm_request
      |> request.set_method(http.Post)
      |> request.set_body(json.to_string(payload))
      |> request.set_header("Content-Type", "application/json")

    use _confirm_response <- result.try(
      httpc.send(req) |> result.map_error(HttpError),
    )
    Ok(payment_webhook)
  }
  case result {
    Ok(payment) -> {
      io.println("OK")

      // Move payment from payments to confirmations using SQLite
      case
        database.move_payment_to_confirmations(
          ctx.db_conn,
          payment.transaction_id,
        )
      {
        Ok(_) -> {
          io.println("Payment moved to confirmations successfully")
          let body = string_tree.from_string(payment.transaction_id)
          wisp.html_response(body, 200)
        }
        Error(database.PaymentNotFound) -> {
          io.println("Payment not found in database")
          let body = string_tree.from_string("<h1>Payment not found</h1>")
          wisp.html_response(body, 404)
        }
        Error(database.SqliteError(_)) -> {
          io.println("Database error while moving payment")
          let body = string_tree.from_string("<h1>Database error</h1>")
          wisp.html_response(body, 500)
        }
      }
    }
    Error(PaymentIdMismatch) -> {
      io.println(
        "Payment data mismatch - webhook data doesn't match stored payment",
      )
      let body = string_tree.from_string("<h1>Payment data mismatch</h1>")
      wisp.html_response(body, 400)
    }
    Error(InvalidPaymentData) -> {
      io.println("Invalid payment data - cancelling payment")

      // Get the transaction_id from the decoded webhook for cancellation
      case decode.run(json, decode_payment_webhook()) {
        Ok(payment_webhook) -> {
          // Send cancellation request
          let payload =
            json.object([
              #("transaction_id", json.string(payment_webhook.transaction_id)),
            ])

          let assert Ok(cancel_request) =
            request.to("http://localhost:5001/cancelar")
          let cancel_req =
            cancel_request
            |> request.set_method(http.Post)
            |> request.set_body(json.to_string(payload))
            |> request.set_header("Content-Type", "application/json")

          case httpc.send(cancel_req) {
            Ok(_) -> {
              // Move payment to cancellations table
              case
                database.move_payment_to_cancellations(
                  ctx.db_conn,
                  payment_webhook.transaction_id,
                )
              {
                Ok(_) -> {
                  io.println("Payment cancelled and moved to cancellations")
                  let body =
                    string_tree.from_string("<h1>Payment cancelled</h1>")
                  wisp.html_response(body, 400)
                }
                Error(_) -> {
                  io.println("Error moving payment to cancellations")
                  let body =
                    string_tree.from_string("<h1>Error cancelling payment</h1>")
                  wisp.html_response(body, 400)
                }
              }
            }
            Error(_) -> {
              io.println("Error sending cancellation request")
              let body =
                string_tree.from_string("<h1>Error cancelling payment</h1>")
              wisp.html_response(body, 400)
            }
          }
        }
        Error(_) -> {
          io.println("Error decoding payment for cancellation")
          let body =
            string_tree.from_string("<h1>Error processing webhook</h1>")
          wisp.html_response(body, 400)
        }
      }
    }
    Error(DecodeError(_)) -> {
      io.println(
        "JSON decode error - attempting cancellation if transaction_id available",
      )

      // Try to extract transaction_id for cancellation even if other fields are missing
      case decode.run(json, decode_transaction_id()) {
        Ok(transaction_id) -> {
          io.println(
            "Found transaction_id in malformed JSON: " <> transaction_id,
          )

          // Send cancellation request
          let payload =
            json.object([#("transaction_id", json.string(transaction_id))])

          let assert Ok(cancel_request) =
            request.to("http://localhost:5001/cancelar")
          let cancel_req =
            cancel_request
            |> request.set_method(http.Post)
            |> request.set_body(json.to_string(payload))
            |> request.set_header("Content-Type", "application/json")

          case httpc.send(cancel_req) {
            Ok(_) -> {
              // Move payment to cancellations table if it exists
              case
                database.move_payment_to_cancellations(
                  ctx.db_conn,
                  transaction_id,
                )
              {
                Ok(_) -> {
                  io.println("Payment cancelled due to missing fields")
                  let body =
                    string_tree.from_string(
                      "<h1>Payment cancelled - missing fields</h1>",
                    )
                  wisp.html_response(body, 400)
                }
                Error(_) -> {
                  io.println("Transaction not found for cancellation")
                  let body =
                    string_tree.from_string("<h1>Error processing webhook</h1>")
                  wisp.html_response(body, 400)
                }
              }
            }
            Error(_) -> {
              io.println("Error sending cancellation request")
              let body =
                string_tree.from_string("<h1>Error processing webhook</h1>")
              wisp.html_response(body, 400)
            }
          }
        }
        Error(_) -> {
          io.println("Cannot extract transaction_id from malformed JSON")
          let body =
            string_tree.from_string("<h1>Error processing webhook</h1>")
          wisp.html_response(body, 400)
        }
      }
    }
    Error(_) -> {
      io.println("Error")
      let body = string_tree.from_string("<h1>Error processing webhook</h1>")
      wisp.html_response(body, 400)
    }
  }
}
