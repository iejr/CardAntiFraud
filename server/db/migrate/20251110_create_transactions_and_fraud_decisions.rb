class CreateTransactionsAndFraudDecisions < ActiveRecord::Migration[7.0]
  def change
    create_table :transactions do |t|
      t.string  :payment_uuid, null: false
      t.datetime :event_timestamp, null: false

      t.bigint  :amount, null: false
      t.string  :currency, null: false

      t.string  :payment_method_type
      t.string  :card_number_hashed, null: false, index: true

      t.string  :merchant_uuid, null: false, index: true
      t.string  :merchant_mcc

      t.string  :customer_email
      t.string  :customer_ip, index: true

      t.json    :raw_payload, null: false, default: {}

      t.timestamps
    end

    create_table :fraud_decisions do |t|
      t.integer :transaction_id, null: false, index: true
      t.string  :decision, null: false # "accept" or "decline"
      t.json    :reasons, default: []
      t.json    :metrics_snapshot, default: {}
      t.timestamps
    end

    add_index :transactions, [:card_number_hashed, :merchant_uuid, :created_at], name: 'idx_card_merchant_created_at'
    add_index :transactions, [:card_number_hashed, :created_at], name: 'idx_card_created_at'
    add_index :transactions, [:customer_ip, :merchant_uuid, :created_at], name: 'idx_ip_merchant_created_at'
    add_index :transactions, [:customer_ip, :created_at], name: 'idx_ip_created_at'
  end
end
