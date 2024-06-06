use aiken/transaction.{ScriptContext}
use types.{InterestDatum}
use utils.{transaction_signed}

type Redeemer {
  action: Int,
}

validator {
  fn interest(
    datum: InterestDatum,
    _redeemer: Redeemer,
    ctx: ScriptContext,
  ) -> Bool {
    transaction_signed(ctx, datum.lender_address_hash)
  }
}
