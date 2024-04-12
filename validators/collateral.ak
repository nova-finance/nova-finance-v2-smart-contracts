use aiken/dict
use aiken/list
use aiken/transaction.{ScriptContext, Transaction}
use aiken/transaction/credential.{StakeCredential}
use types.{CollateralDatum}
use utils

type CollateralRedeemer {
  PayBackLoan
  LiquidateCollateral
}

validator(stake_credential: StakeCredential) {
  fn loan(
    datum: CollateralDatum,
    redeemer: CollateralRedeemer,
    ctx: ScriptContext,
  ) -> Bool {
    when redeemer is {
      PayBackLoan -> {
        let Transaction { withdrawals, .. } = ctx.transaction
        // validate that an Order can be spent if there's a `Collateral` validator in the `withdrawals`
        dict.has_key(withdrawals, stake_credential)
      }

      LiquidateCollateral -> {
        let must_be_signed_by_lender =
          list.has(ctx.transaction.extra_signatories, datum.lender_address_hash)
        let deadline_passed =
          datum.loan_duration + datum.lend_time < utils.get_lower_bound(
            ctx.transaction.validity_range,
          )
        must_be_signed_by_lender && deadline_passed
      }
    }
  }
}
