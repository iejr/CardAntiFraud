# Project Overview

This project is a Ruby on Rails application that implements a card fraud check logic. It evaluates transactions to determine if they should be accepted or declined based on predefined rules.

## Installation Instructions

1. Ensure you have Ruby and Rails installed on your system.
2. Clone the repository:
   ```bash
   git clone https://github.com/iejr/CardAntiFraud.git
   ```
3. Navigate to the project directory:
   ```bash
   cd CardAntiFraud/server
   ```
4. Install the required gems:
   ```bash
   bundle install
   ```

## Configuration

- Ensure the `fraud_rules.yml` file is properly configured with the necessary rules for fraud checking.

## Database Setup

1. Create the database:
   ```bash
   rails db:create
   ```
2. Run the migrations:
   ```bash
   rails db:migrate
   ```

## Running the Application

Start the Rails server:
```bash
rails server
```

## Testing

Run the test suite to ensure everything is working correctly:
```bash
rspec
```

## Fraud Check Logic

The application includes a fraud check service implemented in the `FraudChecker` class. This service evaluates transactions to determine if they should be accepted or declined based on predefined rules.

### Main Logic

- **Initialization**: The `FraudChecker` is initialized with transaction parameters and loads rules from the `fraud_rules.yml` configuration file.
- **Transaction Attributes**: Builds transaction attributes including payment method, merchant, and customer details.
- **Decision Making**: The `run` method is the main entry point, returning a decision of "accept" or "decline" with a reason.
- **Checks Performed**:
  - `check_card_merchant`: Checks the number of transactions for a card at a specific merchant.
  - `check_card_global`: Checks the number of transactions for a card globally.
  - `check_card_low_value`: Checks the number of low-value transactions for a card.
  - `check_ip_merchant`: Checks the number of transactions from an IP at a specific merchant.
  - `check_ip_global`: Checks the number of transactions from an IP globally.
  - `check_ip_low_value`: Checks the number of low-value transactions from an IP.

## Deployment Instructions

Provide instructions for deploying the application.

## Contributing

Provide guidelines for contributing to the project.

## License

Specify the license under which the project is distributed.
