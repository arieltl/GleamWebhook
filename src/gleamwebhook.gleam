import app/database
import app/router
import app/web.{Context, PaymentWebhook}
import gleam/erlang/process
import gleam/io
import mist
import wisp
import wisp/wisp_mist

pub fn main() {
  wisp.configure_logger()

  // Initialize database
  let assert Ok(db_conn) = database.init_database("webhook.db")

  // Clear all existing data from tables
  case database.clear_all_tables(db_conn) {
    Ok(_) -> io.println("Database tables cleared successfully")
    Error(_err) -> {
      io.println("Error clearing database tables")
      io.println_error("Database error occurred")
      Nil
    }
  }

  // Create list of initial pending payments
  let initial_pending_payments = [
    PaymentWebhook(
      "abc123",
      "49.90",
      "BRL",
      "payment_success",
      "2023-10-01T12:00:00Z",
    ),
    PaymentWebhook(
      "abc123a",
      "29.90",
      "BRL",
      "payment_success",
      "2023-10-01T13:00:00Z",
    ),
    PaymentWebhook(
      "abc123abc",
      "0.00",
      "BRL",
      "payment_success",
      "2023-10-01T14:00:00Z",
    ),
  ]

  // Insert initial pending payments into database
  case database.insert_payments(db_conn, initial_pending_payments) {
    Ok(_) -> io.println("Initial pending payments inserted successfully")
    Error(_err) -> {
      io.println("Error inserting initial pending payments")
      io.println_error("Database error occurred")
      Nil
    }
  }

  // Create context with database connection and webhook token
  let ctx = Context(db_conn, "meu-token-secreto")

  let handler = router.handle_request(_, ctx)
  let assert Ok(_) =
    wisp_mist.handler(handler, "secret_key")
    |> mist.new
    |> mist.port(5000)
    |> mist.start_http

  process.sleep_forever()
}
