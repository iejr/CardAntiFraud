class FraudChecker
  attr_reader :params, :tx_attrs, :rules, :now

  def initialize(params)
    @params = params.deep_symbolize_keys
    @rules = Rails.application.config_for(:fraud_rules)["rules"]
    @now = Time.parse(params[:timestamp]).utc rescue Time.current.utc
  end

  # main entry: returns {decision: "accept"|"decline", reasons: [], metrics: {}}
  def run
    build_tx_attrs
    check_metrics

    # metrics = snapshot_metrics
    # reasons = []

    # # perform checks, append reasons if tripped
    # rules.each do |name, rule|
    #   case name.to_s
    #   when "card_merchant"
    #     count = metrics[:card_merchant_count]
    #     if count > rule[:threshold]
    #       reasons << "too_many_tx_for_card_at_merchant (#{count} > #{rule['threshold']})"
    #     end
    #   when "card_global"
    #     count = metrics[:card_global_count]
    #     if count > rule[:threshold]
    #       reasons << "too_many_tx_for_card (#{count} > #{rule['threshold']})"
    #     end
    #   when "card_low_value"
    #     count = metrics[:card_low_value_count]
    #     if count > rule[:threshold]
    #       reasons << "too_many_low_value_tx_for_card (#{count} > #{rule['threshold']})"
    #     end
    #   when "ip_merchant"
    #     count = metrics[:ip_merchant_count]
    #     if count > rule[:threshold]
    #       reasons << "too_many_tx_from_ip_at_merchant (#{count} > #{rule['threshold']})"
    #     end
    #   when "ip_global"
    #     count = metrics[:ip_global_count]
    #     if count > rule[:threshold]
    #       reasons << "too_many_tx_from_ip (#{count} > #{rule['threshold']})"
    #     end
    #   when "ip_low_value"
    #     count = metrics[:ip_low_value_count]
    #     if count > rule[:threshold]
    #       reasons << "too_many_low_value_tx_from_ip (#{count} > #{rule['threshold']})"
    #     end
    #   end
    # end

    # decision = reasons.empty? ? "accept" : "decline"
    # { decision: decision, reasons: reasons, metrics: metrics }
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
    
    if !check_card_merchant(rules, card, merchant, ip)
      return { decision: "decline", reason: "too_many_tx_for_card_at_merchant" }
    end

    if !check_card_global(rules, card, merchant, ip)
      return { decision: "decline", reason: "too_many_tx_for_card" }
    end

    if !check_card_low_value(rules, card, merchant, ip)
      return { decision: "decline", reason: "too_many_low_value_tx_for_card" }
    end

    if !check_ip_merchant(rules, card, merchant, ip)
      return { decision: "decline", reason: "too_many_tx_from_ip_at_merchant" }
    end

    if !check_ip_global(rules, card, merchant, ip)
      return { decision: "decline", reason: "too_many_tx_from_ip" }
    end

    if !check_ip_low_value(rules, card, merchant, ip)
      return { decision: "decline", reason: "too_many_low_value_tx_from_ip" }
    end

    { decision: "accept" }
  end

  def check_card_merchant(rules, card, merchant, ip)
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

    Rails.logger.info({
      now: now,
      window_size: window_size,
      window_start: window_start,
      count: count,
      threshold: rule[:threshold]
    })

    count < rule[:threshold]
  end

  def check_card_global(rules, card, merchant, ip)
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

  def check_card_low_value(rules, card, merchant, ip)
    rule = rules[:card_low_value]
    if !rule
      return true
    end

    window_size = rule[:window_seconds].to_i
    window_start = now - window_size.seconds
    low_value_threshold = rule[:low_value_amount]
    count = Transaction
      .where(card_number_hashed: card)
      .where('amount <= ?', low_value_threshold)
      .where('event_timestamp >= ?', window_start)
      .count

    count < rule[:threshold]
  end

  def check_ip_merchant(rules, card, merchant, ip)
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

  def check_ip_global(rules, card, merchant, ip)
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

  def check_ip_low_value(rules, card, merchant, ip)
    rule = rules[:ip_low_value]
    if !rule
      return true
    end

    window_size = rule[:window_seconds].to_i
    window_start = now - window_size.seconds
    low_value_threshold = rule[:low_value_amount]
    count = Transaction
      .where(customer_ip: ip)
      .where('amount <= ?', low_value_threshold)
      .where('event_timestamp >= ?', window_start)
      .count

    count < rule[:threshold]
  end

  # snapshot metrics by running efficient SQL counts within configured window(s)
  def snapshot_metrics
    # compute earliest timestamp for each rule; for now we use window_seconds from card_merchant rule (or default)
    # For simplicity we'll use the max window across rules to minimize queries. Could be optimized per rule.
    max_window = rules.values.map { |r| r["window_seconds"].to_i }.max || 60
    window_start = now - max_window.seconds

    card = tx_attrs[:card_number_hashed]
    merchant = tx_attrs[:merchant_uuid]
    ip = tx_attrs[:customer_ip]
    low_value_threshold = (rules["card_low_value"] && rules["card_low_value"]["low_value_amount"]) ||
                           (rules["ip_low_value"] && rules["ip_low_value"]["low_value_amount"]) || 0

    # All counts refer to transactions that occurred after window_start.
    txs = Transaction.arel_table

    # 1) card + merchant
    card_merchant_count = Transaction
      .where(card_number_hashed: card, merchant_uuid: merchant)
      .where('event_timestamp >= ?', window_start)
      .count

    # 2) card global
    card_global_count = Transaction
      .where(card_number_hashed: card)
      .where('event_timestamp >= ?', window_start)
      .count

    # 3) card low value
    card_low_value_count = Transaction
      .where(card_number_hashed: card)
      .where('amount <= ?', low_value_threshold)
      .where('event_timestamp >= ?', window_start)
      .count

    # 4) ip + merchant
    ip_merchant_count = Transaction
      .where(customer_ip: ip, merchant_uuid: merchant)
      .where('event_timestamp >= ?', window_start)
      .count

    # 5) ip global
    ip_global_count = Transaction
      .where(customer_ip: ip)
      .where('event_timestamp >= ?', window_start)
      .count

    # 6) ip low value
    ip_low_value_count = Transaction
      .where(customer_ip: ip)
      .where('amount <= ?', low_value_threshold)
      .where('event_timestamp >= ?', window_start)
      .count

    {
      card_merchant_count: card_merchant_count,
      card_global_count: card_global_count,
      card_low_value_count: card_low_value_count,
      ip_merchant_count: ip_merchant_count,
      ip_global_count: ip_global_count,
      ip_low_value_count: ip_low_value_count,
      window_seconds: max_window
    }
  end
end

