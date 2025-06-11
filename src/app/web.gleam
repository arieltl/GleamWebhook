import sqlight

pub type Context {
  Context(db_conn: sqlight.Connection, webhook_token: String)
}

pub type PaymentWebhook {
  PaymentWebhook(
    transaction_id: String,
    amount: String,
    currency: String,
    event: String,
    timestamp: String,
  )
}
