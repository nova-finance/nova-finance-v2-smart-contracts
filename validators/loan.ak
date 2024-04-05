use aiken/list
use aiken/transaction.{ScriptContext}
use types.{LoanOfferDatum}

type LoanRedeemer {
  CancelLoan
  GetLoan
}

type Redeemer {
  action: LoanRedeemer,
}

validator {
  fn loan(
    datum: LoanOfferDatum,
    redeemer: Redeemer,
    context: ScriptContext,
  ) -> Bool {
    when redeemer.action is {
      // todo
      GetLoan -> False
      // Check original lender is signing the transaction
      CancelLoan -> {
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
