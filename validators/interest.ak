use aiken/list
use aiken/transaction.{ScriptContext}
use types.{InterestDatum}

type Redeemer {
  action: Int,
}

validator {
  fn interest(
    datum: InterestDatum,
    _redeemer: Redeemer,
    ctx: ScriptContext,
  ) -> Bool {
    // To redeem the interest, the transaction must be signed by the original lender
    let must_be_signed_by_lender =
      list.has(ctx.transaction.extra_signatories, datum.lender_address_hash)
    must_be_signed_by_lender
  }
}
