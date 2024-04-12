use aiken/dict
use aiken/list
use aiken/transaction.{ScriptContext, Transaction}
use aiken/transaction/credential.{StakeCredential}
use types.{LoanOfferDatum}

type LoanRedeemer {
  GetLoan
  CancelRequest
}

validator(stake_credential: StakeCredential) {
  fn loan(
    datum: LoanOfferDatum,
    redeemer: LoanRedeemer,
    ctx: ScriptContext,
  ) -> Bool {
    when redeemer is {
      GetLoan -> {
        let Transaction { withdrawals, .. } = ctx.transaction
        // validate that an Order can be spent if there's a `Loan` validator in the `withdrawals`
        dict.has_key(withdrawals, stake_credential)
      }

      CancelRequest -> {
        // Can only be cancelled by the original lender
        let must_be_signed_by_lender =
          list.has(ctx.transaction.extra_signatories, datum.lender_address_hash)
        must_be_signed_by_lender
      }
    }
  }
}
