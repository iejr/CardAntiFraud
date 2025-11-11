class FraudChecker
  attr_reader :params, :tx_attrs, :rules, :now

  def initialize(params)
    @params = params.deep_symbolize_keys
    @rules = Rails.application.config_for(:fraud_rules)["rules"]
    @now = Time.parse(params[:timestamp]).utc rescue Time.current.utc
  end

  # main entry: returns {decision: "accept"|"decline", reason: string}
  def run
    build_tx_attrs
    check_metrics
  end

  private

  def build_tx_attrs
    pm = params[:payment_method] || {}
    merchant = params[:merchant] || {}
    customer = params[:customer] || {}
    timestamp = Time.parse(params[:timestamp]).utc rescue Time.current.utc

    @tx_attrs = {
      payment_uuid: params[:payment_uuid],
      event_timestamp: timestamp,
      amount: params[:amount].to_i,
      currency: params[:currency],
      payment_method_type: pm[:type],
      card_number_hashed: pm[:card_number_hashed],
      merchant_uuid: merchant[:uuid],
      merchant_mcc: merchant[:mcc_code],
      customer_email: customer[:email],
      customer_ip: customer[:ip_address],
      raw_payload: params
    }
  end

  def check_metrics
    # Loop rules from config and check the event one by one; 
    # Return declined with reason when any rule check fails, otherwise return accept
    card = tx_attrs[:card_number_hashed]
    merchant = tx_attrs[:merchant_uuid]
    ip = tx_attrs[:customer_ip]
    amount = tx_attrs[:amount].to_i
    
    if !check_card_merchant(rules, card, merchant)
      return { decision: "decline", reason: "too_many_tx_for_card_at_merchant" }
    end

    if !check_card_global(rules, card, merchant)
      return { decision: "decline", reason: "too_many_tx_for_card" }
    end

    if !check_card_low_value(rules, card, merchant, amount)
      return { decision: "decline", reason: "too_many_low_value_tx_for_card" }
    end

    if !check_ip_merchant(rules, merchant, ip)
      return { decision: "decline", reason: "too_many_tx_from_ip_at_merchant" }
    end

    if !check_ip_global(rules, merchant, ip)
      return { decision: "decline", reason: "too_many_tx_from_ip" }
    end

    if !check_ip_low_value(rules, merchant, ip, amount)
      return { decision: "decline", reason: "too_many_low_value_tx_from_ip" }
    end

    { decision: "accept" }
  end

  def check_card_merchant(rules, card, merchant)
    rule = rules[:card_merchant]
    if !rule
      return true
    end

    window_size = rule[:window_seconds].to_i
    window_start = now - window_size.seconds
    count = Transaction
      .where(card_number_hashed: card, merchant_uuid: merchant)
      .where('event_timestamp >= ?', window_start)
      .count

    count < rule[:threshold]
  end

  def check_card_global(rules, card, merchant)
    rule = rules[:card_global]
    if !rule
      return true
    end

    window_size = rule[:window_seconds].to_i
    window_start = now - window_size.seconds
    count = Transaction
      .where(card_number_hashed: card)
      .where('event_timestamp >= ?', window_start)
      .count

    count < rule[:threshold]
  end

  def check_card_low_value(rules, card, merchant, amount)
    rule = rules[:card_low_value]
    if !rule
      return true
    end

    window_size = rule[:window_seconds].to_i
    window_start = now - window_size.seconds
    low_value_threshold = rule[:low_value_amount]
    if amount > low_value_threshold
      return true
    end

    count = Transaction
      .where(card_number_hashed: card)
      .where('amount <= ?', low_value_threshold)
      .where('event_timestamp >= ?', window_start)
      .count

    count < rule[:threshold]
  end

  def check_ip_merchant(rules, merchant, ip)
    rule = rules[:ip_merchant]
    if !rule
      return true
    end

    window_size = rule[:window_seconds].to_i
    window_start = now - window_size.seconds
    count = Transaction
      .where(customer_ip: ip, merchant_uuid: merchant)
      .where('event_timestamp >= ?', window_start)
      .count

    count < rule[:threshold]
  end

  def check_ip_global(rules, merchant, ip)
    rule = rules[:ip_global]
    if !rule
      return true
    end

    window_size = rule[:window_seconds].to_i
    window_start = now - window_size.seconds
    count = Transaction
      .where(customer_ip: ip)
      .where('event_timestamp >= ?', window_start)
      .count

    count < rule[:threshold]
  end

  def check_ip_low_value(rules, merchant, ip, amount)
    rule = rules[:ip_low_value]
    if !rule
      return true
    end

    window_size = rule[:window_seconds].to_i
    window_start = now - window_size.seconds
    low_value_threshold = rule[:low_value_amount]
    if amount > low_value_threshold
      return true
    end

    count = Transaction
      .where(customer_ip: ip)
      .where('amount <= ?', low_value_threshold)
      .where('event_timestamp >= ?', window_start)
      .count

    count < rule[:threshold]
  end
end
