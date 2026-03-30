import os

with open('lib/screens/deposit_page.dart', 'r') as f:
    text = f.read()

text = text.replace('DepositPage', 'WithdrawPage')
text = text.replace('_DepositPageState', '_WithdrawPageState')
text = text.replace('Deposit', 'Withdraw')
text = text.replace('deposit', 'withdraw')
text = text.replace('Cancel Withdraw', 'Cancel Withdrawal')
text = text.replace("'To'", "'From'")
text = text.replace("['Deriv', 'MT5', 'Binance']", "['Deriv', 'MT5']")

# Fix any Withdrawinging that might result from deposite -> withdraw + ing
text = text.replace('Withdrawinging', 'Withdrawing')

with open('lib/screens/withdraw_page.dart', 'w') as f:
    f.write(text)
print("withdraw_page.dart created successfully.")
