class Transaction < ApplicationRecord
  self.table_name = 'transactions'
  # validations
  validates :payment_uuid, :card_number_hashed, :merchant_uuid, :amount, :currency, presence: true
end

# app/models/fraud_decision.rb
class FraudDecision < ApplicationRecord
  self.table_name = 'fraud_decisions'
  belongs_to :payment_transaction, class_name: 'Transaction', foreign_key: :transaction_id
end
