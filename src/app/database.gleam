import app/web.{type PaymentWebhook, PaymentWebhook}
import gleam/dynamic/decode
import gleam/list
import gleam/result
import sqlight

pub type DatabaseError {
  SqliteError(sqlight.Error)
  PaymentNotFound
}

// Initialize database with tables
pub fn init_database(
  db_path: String,
) -> Result(sqlight.Connection, sqlight.Error) {
  use conn <- result.try(sqlight.open(db_path))

  let payments_table_sql =
    "
    CREATE TABLE IF NOT EXISTS payments (
      transaction_id TEXT PRIMARY KEY,
      amount TEXT NOT NULL,
      currency TEXT NOT NULL,
      event TEXT NOT NULL,
      timestamp TEXT NOT NULL
    );
  "

  let confirmations_table_sql =
    "
    CREATE TABLE IF NOT EXISTS confirmations (
      transaction_id TEXT PRIMARY KEY,
      amount TEXT NOT NULL,
      currency TEXT NOT NULL,
      event TEXT NOT NULL,
      timestamp TEXT NOT NULL,
      confirmed_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  "

  let cancellations_table_sql =
    "
    CREATE TABLE IF NOT EXISTS cancellations (
      transaction_id TEXT PRIMARY KEY,
      amount TEXT NOT NULL,
      currency TEXT NOT NULL,
      event TEXT NOT NULL,
      timestamp TEXT NOT NULL,
      cancelled_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  "

  use _ <- result.try(sqlight.exec(payments_table_sql, on: conn))
  use _ <- result.try(sqlight.exec(confirmations_table_sql, on: conn))
  use _ <- result.try(sqlight.exec(cancellations_table_sql, on: conn))

  Ok(conn)
}

// Clear all data from all tables
pub fn clear_all_tables(conn: sqlight.Connection) -> Result(Nil, sqlight.Error) {
  use _ <- result.try(sqlight.exec("DELETE FROM payments;", on: conn))
  use _ <- result.try(sqlight.exec("DELETE FROM confirmations;", on: conn))
  use _ <- result.try(sqlight.exec("DELETE FROM cancellations;", on: conn))
  Ok(Nil)
}

// Insert a payment into the payments table
pub fn insert_payment(
  conn: sqlight.Connection,
  payment: PaymentWebhook,
) -> Result(Nil, sqlight.Error) {
  let sql =
    "
    INSERT OR IGNORE INTO payments (transaction_id, amount, currency, event, timestamp)
    VALUES (?1, ?2, ?3, ?4, ?5)
  "

  let decoder = decode.success(Nil)

  sqlight.query(
    sql,
    on: conn,
    with: [
      sqlight.text(payment.transaction_id),
      sqlight.text(payment.amount),
      sqlight.text(payment.currency),
      sqlight.text(payment.event),
      sqlight.text(payment.timestamp),
    ],
    expecting: decoder,
  )
  |> result.map(fn(_) { Nil })
}

// Insert multiple payments into the payments table
pub fn insert_payments(
  conn: sqlight.Connection,
  payments: List(PaymentWebhook),
) -> Result(Nil, sqlight.Error) {
  use _ <- result.try(
    list.try_each(payments, fn(payment) { insert_payment(conn, payment) }),
  )
  Ok(Nil)
}

// Move payment from payments to confirmations
pub fn move_payment_to_confirmations(
  conn: sqlight.Connection,
  transaction_id: String,
) -> Result(Nil, DatabaseError) {
  // Start a transaction
  use _ <- result.try(
    sqlight.exec("BEGIN TRANSACTION;", on: conn)
    |> result.map_error(SqliteError),
  )

  // Get the payment from payments table
  let get_payment_sql =
    "
    SELECT transaction_id, amount, currency, event, timestamp 
    FROM payments 
    WHERE transaction_id = ?1
  "

  let payment_decoder = {
    use transaction_id <- decode.field(0, decode.string)
    use amount <- decode.field(1, decode.string)
    use currency <- decode.field(2, decode.string)
    use event <- decode.field(3, decode.string)
    use timestamp <- decode.field(4, decode.string)
    decode.success(#(transaction_id, amount, currency, event, timestamp))
  }

  use payment_rows <- result.try(
    sqlight.query(
      get_payment_sql,
      on: conn,
      with: [sqlight.text(transaction_id)],
      expecting: payment_decoder,
    )
    |> result.map_error(SqliteError),
  )

  case payment_rows {
    [] -> {
      let _ = sqlight.exec("ROLLBACK;", on: conn)
      Error(PaymentNotFound)
    }
    [#(tid, amount, currency, event, timestamp)] -> {
      // Insert into confirmations table
      let insert_confirmation_sql =
        "
        INSERT INTO confirmations (transaction_id, amount, currency, event, timestamp)
        VALUES (?1, ?2, ?3, ?4, ?5)
      "

      let nil_decoder = decode.success(Nil)

      use _ <- result.try(
        sqlight.query(
          insert_confirmation_sql,
          on: conn,
          with: [
            sqlight.text(tid),
            sqlight.text(amount),
            sqlight.text(currency),
            sqlight.text(event),
            sqlight.text(timestamp),
          ],
          expecting: nil_decoder,
        )
        |> result.map_error(SqliteError)
        |> result.map(fn(_) { Nil }),
      )

      // Delete from payments table
      let delete_payment_sql = "DELETE FROM payments WHERE transaction_id = ?1"

      use _ <- result.try(
        sqlight.query(
          delete_payment_sql,
          on: conn,
          with: [sqlight.text(transaction_id)],
          expecting: nil_decoder,
        )
        |> result.map_error(SqliteError)
        |> result.map(fn(_) { Nil }),
      )

      // Commit transaction
      use _ <- result.try(
        sqlight.exec("COMMIT;", on: conn) |> result.map_error(SqliteError),
      )

      Ok(Nil)
    }
    _ -> {
      let _ = sqlight.exec("ROLLBACK;", on: conn)
      Error(PaymentNotFound)
    }
  }
}

// Move payment from payments to cancellations
pub fn move_payment_to_cancellations(
  conn: sqlight.Connection,
  transaction_id: String,
) -> Result(Nil, DatabaseError) {
  // Start a transaction
  use _ <- result.try(
    sqlight.exec("BEGIN TRANSACTION;", on: conn)
    |> result.map_error(SqliteError),
  )

  // Get the payment from payments table
  let get_payment_sql =
    "
    SELECT transaction_id, amount, currency, event, timestamp 
    FROM payments 
    WHERE transaction_id = ?1
  "

  let payment_decoder = {
    use transaction_id <- decode.field(0, decode.string)
    use amount <- decode.field(1, decode.string)
    use currency <- decode.field(2, decode.string)
    use event <- decode.field(3, decode.string)
    use timestamp <- decode.field(4, decode.string)
    decode.success(#(transaction_id, amount, currency, event, timestamp))
  }

  use payment_rows <- result.try(
    sqlight.query(
      get_payment_sql,
      on: conn,
      with: [sqlight.text(transaction_id)],
      expecting: payment_decoder,
    )
    |> result.map_error(SqliteError),
  )

  case payment_rows {
    [] -> {
      let _ = sqlight.exec("ROLLBACK;", on: conn)
      Error(PaymentNotFound)
    }
    [#(tid, amount, currency, event, timestamp)] -> {
      // Insert into cancellations table
      let insert_cancellation_sql =
        "
        INSERT INTO cancellations (transaction_id, amount, currency, event, timestamp)
        VALUES (?1, ?2, ?3, ?4, ?5)
      "

      let nil_decoder = decode.success(Nil)

      use _ <- result.try(
        sqlight.query(
          insert_cancellation_sql,
          on: conn,
          with: [
            sqlight.text(tid),
            sqlight.text(amount),
            sqlight.text(currency),
            sqlight.text(event),
            sqlight.text(timestamp),
          ],
          expecting: nil_decoder,
        )
        |> result.map_error(SqliteError)
        |> result.map(fn(_) { Nil }),
      )

      // Delete from payments table
      let delete_payment_sql = "DELETE FROM payments WHERE transaction_id = ?1"

      use _ <- result.try(
        sqlight.query(
          delete_payment_sql,
          on: conn,
          with: [sqlight.text(transaction_id)],
          expecting: nil_decoder,
        )
        |> result.map_error(SqliteError)
        |> result.map(fn(_) { Nil }),
      )

      // Commit transaction
      use _ <- result.try(
        sqlight.exec("COMMIT;", on: conn) |> result.map_error(SqliteError),
      )

      Ok(Nil)
    }
    _ -> {
      let _ = sqlight.exec("ROLLBACK;", on: conn)
      Error(PaymentNotFound)
    }
  }
}

// Get all payments from payments table
pub fn get_payments(
  conn: sqlight.Connection,
) -> Result(List(PaymentWebhook), sqlight.Error) {
  let sql =
    "SELECT transaction_id, amount, currency, event, timestamp FROM payments"

  let payment_decoder = {
    use transaction_id <- decode.field(0, decode.string)
    use amount <- decode.field(1, decode.string)
    use currency <- decode.field(2, decode.string)
    use event <- decode.field(3, decode.string)
    use timestamp <- decode.field(4, decode.string)
    decode.success(PaymentWebhook(
      transaction_id,
      amount,
      currency,
      event,
      timestamp,
    ))
  }

  sqlight.query(sql, on: conn, with: [], expecting: payment_decoder)
}

// Get a specific payment by transaction_id
pub fn get_payment_by_id(
  conn: sqlight.Connection,
  transaction_id: String,
) -> Result(PaymentWebhook, DatabaseError) {
  let sql =
    "SELECT transaction_id, amount, currency, event, timestamp FROM payments WHERE transaction_id = ?1"

  let payment_decoder = {
    use transaction_id <- decode.field(0, decode.string)
    use amount <- decode.field(1, decode.string)
    use currency <- decode.field(2, decode.string)
    use event <- decode.field(3, decode.string)
    use timestamp <- decode.field(4, decode.string)
    decode.success(PaymentWebhook(
      transaction_id,
      amount,
      currency,
      event,
      timestamp,
    ))
  }

  use rows <- result.try(
    sqlight.query(
      sql,
      on: conn,
      with: [sqlight.text(transaction_id)],
      expecting: payment_decoder,
    )
    |> result.map_error(SqliteError),
  )

  case rows {
    [payment] -> Ok(payment)
    [] -> Error(PaymentNotFound)
    _ -> Error(PaymentNotFound)
    // Multiple payments with same ID shouldn't happen due to PRIMARY KEY
  }
}

// Get all confirmations
pub fn get_confirmations(
  conn: sqlight.Connection,
) -> Result(List(String), sqlight.Error) {
  let sql = "SELECT transaction_id FROM confirmations"

  let confirmation_decoder = {
    use transaction_id <- decode.field(0, decode.string)
    decode.success(transaction_id)
  }

  sqlight.query(sql, on: conn, with: [], expecting: confirmation_decoder)
}

// Get all cancellations
pub fn get_cancellations(
  conn: sqlight.Connection,
) -> Result(List(String), sqlight.Error) {
  let sql = "SELECT transaction_id FROM cancellations"

  let cancellation_decoder = {
    use transaction_id <- decode.field(0, decode.string)
    decode.success(transaction_id)
  }

  sqlight.query(sql, on: conn, with: [], expecting: cancellation_decoder)
}
