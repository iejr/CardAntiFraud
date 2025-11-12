class FraudChecksController < ApplicationController
  skip_before_action :verify_authenticity_token
  rescue_from StandardError, with: :handle_error

  def create
    payload = params.to_unsafe_h.deep_symbolize_keys
    checker = FraudChecker.new(payload)
    result = checker.run
    
    Rails.logger.info({
      checker_run: result
    })

    # persist transaction and decision
    tx = Transaction.create!(checker.tx_attrs)
    FraudDecision.create!(
      transaction_id: tx.id,
      decision: result[:decision],
      reason: result[:reason],
    )

    log_request(tx, result)

    status_code = result[:decision] == "accept" ? :ok : :forbidden
    render json: { decision: result[:decision], reason: result[:reason] }, status: status_code
  end

  private

  def log_request(tx, result)
    Rails.logger.info({
      event: "fraud_check",
      payment_uuid: tx.payment_uuid,
      transaction_id: tx.id,
      amount: tx.amount,
      card_hash: tx.card_number_hashed,
      merchant_uuid: tx.merchant_uuid,
      customer_ip: tx.customer_ip,
      decision: result[:decision],
      reason: result[:reason],
    }.to_json)
  end

  def handle_error(e)
    Rails.logger.error("fraud_check_error: #{e.class} #{e.message}\n#{e.backtrace.first(10).join("\n")}")
    render json: { error: "internal_error" }, status: :internal_server_error
  end
end

