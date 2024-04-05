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
    context: ScriptContext,
  ) -> Bool {
    let must_be_signed_by_lender =
      list.has(context.transaction.extra_signatories, datum.lender_address_hash)
    must_be_signed_by_lender
  }
}
