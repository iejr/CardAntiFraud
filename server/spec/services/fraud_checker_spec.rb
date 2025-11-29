require 'rails_helper'

RSpec.describe FraudChecker, type: :service do
  let(:now) { Time.current.utc }
  let(:base_attrs) do
    {
      "payment_uuid" => SecureRandom.uuid,
      "timestamp" => now.iso8601,
      "amount" => 5000,
      "currency" => "JPY",
      "payment_method" => {
        "type" => "credit_card",
        "card_number_hashed" => "card123"
      },
      "merchant" => {
        "uuid" => "merchant123",
        "mcc_code" => "5812"
      },
      "customer" => {
        "email" => "someone@example.com",
        "ip_address" => "203.0.113.42"
      }
    }
  end

  before do
    Transaction.delete_all
    FraudDecision.delete_all
  end

  def perform(attrs = base_attrs)
    FraudChecker.new(attrs).run
  end

  # ------------------------------------------------------------------------
  # 1. Same card & same merchant velocity
  # ------------------------------------------------------------------------
  it 'declines if too many same card + same merchant transactions in window' do
    5.times do
      Transaction.create!(
        payment_uuid: "fakeuuid",
        card_number_hashed: "card123",
        merchant_uuid: "merchant123",
        event_timestamp: now - 30.seconds,
        amount: 1000,
        currency: "JPY"
      )
    end

    decision = perform
    expect(decision[:decision]).to eq("decline")
    expect(decision[:reason]).to match(/too_many_tx_for_card_at_merchant/)
  end

  # ------------------------------------------------------------------------
  # 2. Same card (any merchant)
  # ------------------------------------------------------------------------
  it 'declines if same card exceeds global threshold' do
    10.times do |i|
      Transaction.create!(
        payment_uuid: "fakeuuid",
        card_number_hashed: "card123",
        merchant_uuid: "merchant#{i}",
        event_timestamp: now - 20.seconds,
        amount: 1000,
        currency: "JPY"
      )
    end

    decision = perform
    expect(decision[:decision]).to eq("decline")
    expect(decision[:reason]).to match(/too_many_tx_for_card/)
  end

  # ------------------------------------------------------------------------
  # 3. Same card in low-value transactions
  # ------------------------------------------------------------------------
  it 'declines if same card exceeds low-value threshold' do
    4.times do
      Transaction.create!(
        payment_uuid: "fakeuuid",
        card_number_hashed: "card123",
        merchant_uuid: "merchant123",
        event_timestamp: now - 30.seconds,
        amount: 100,
        currency: "JPY"
      )
    end
    4.times do
      Transaction.create!(
        payment_uuid: "fakeuuid",
        card_number_hashed: "card123",
        merchant_uuid: "merchant456",
        event_timestamp: now - 20.seconds,
        amount: 100,
        currency: "JPY"
      )
    end

    attrs = base_attrs.merge("amount" => 100)
    decision = perform(attrs)
    expect(decision[:decision]).to eq("decline")
    expect(decision[:reason]).to match(/too_many_low_value_tx_for_card/)
  end

  # ------------------------------------------------------------------------
  # 4. Same IP + same merchant
  # ------------------------------------------------------------------------
  it 'declines if too many same ip + same merchant transactions' do
    6.times do
      Transaction.create!(
        payment_uuid: "fakeuuid",
        customer_ip: "203.0.113.42",
        merchant_uuid: "merchant123",
        event_timestamp: now - 40.seconds,
        card_number_hashed: "other_card",
        amount: 1000,
        currency: "JPY"
      )
    end

    decision = perform
    expect(decision[:decision]).to eq("decline")
    expect(decision[:reason]).to match(/too_many_tx_from_ip_at_merchant/)
  end

  # ------------------------------------------------------------------------
  # 5. Same IP (any merchant)
  # ------------------------------------------------------------------------
  it 'declines if same ip exceeds threshold across merchants' do
    12.times do |i|
      Transaction.create!(
        payment_uuid: "fakeuuid",
        customer_ip: "203.0.113.42",
        merchant_uuid: "merchant#{i}",
        event_timestamp: now - 30.seconds,
        card_number_hashed: "another_card",
        amount: 1000,
        currency: "JPY"
      )
    end
    
    decision = perform
    expect(decision[:decision]).to eq("decline")
    expect(decision[:reason]).to match(/too_many_tx_from_ip/)
  end

  # ------------------------------------------------------------------------
  # 6. Same IP in low-value transactions
  # ------------------------------------------------------------------------
  it 'declines if same ip exceeds low-value threshold' do
    5.times do
      Transaction.create!(
        payment_uuid: "fakeuuid",
        customer_ip: "203.0.113.42",
        merchant_uuid: "merchant123",
        event_timestamp: now - 30.seconds,
        card_number_hashed: "some_card",
        amount: 100,
        currency: "JPY"
      )
    end
    5.times do
      Transaction.create!(
        payment_uuid: "fakeuuid",
        customer_ip: "203.0.113.42",
        merchant_uuid: "merchant456",
        event_timestamp: now - 30.seconds,
        card_number_hashed: "some_card",
        amount: 100,
        currency: "JPY"
      )
    end

    attrs = base_attrs.merge("amount" => 100)
    decision = perform(attrs)
    expect(decision[:decision]).to eq("decline")
    expect(decision[:reason]).to match(/too_many_low_value_tx_from_ip/)
  end

  # ------------------------------------------------------------------------
  # 7. Accept when below all thresholds
  # ------------------------------------------------------------------------
  it 'accepts if no velocity rule is triggered' do
    decision = perform
    expect(decision[:decision]).to eq("accept")
  end

  # ------------------------------------------------------------------------
  # 8. Edge case: missing fields, invalid timestamp
  # ------------------------------------------------------------------------
  it 'handles missing timestamp gracefully' do
    attrs = base_attrs.except("timestamp")
    expect { perform(attrs) }.not_to raise_error
  end

  it 'handles malformed input safely' do
    expect { perform({}) }.not_to raise_error
  end
end

