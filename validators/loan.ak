use aiken/list
use aiken/transaction.{ScriptContext}
use types.{LoanOfferDatum}

type LoanRedeemer {
  GetLoan
  CancelRequest
}

validator {
  fn loan(
    datum: LoanOfferDatum,
    redeemer: LoanRedeemer,
    context: ScriptContext,
  ) -> Bool {
    when redeemer is {
      // todo
      GetLoan -> False
      // Check original lender is signing the transaction
      CancelRequest -> {
        let must_be_signed_by_lender =
          list.has(
            context.transaction.extra_signatories,
            datum.lender_address_hash,
          )
        must_be_signed_by_lender
      }
    }
  }
}
