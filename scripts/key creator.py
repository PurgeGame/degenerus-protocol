from eth_account import Account
import secrets

# Function to generate a private key and address
def generate_key_and_address():
    priv = secrets.token_hex(32)
    private_key = "0x" + priv
    acct = Account.from_key(private_key)
    return private_key, acct.address

# Function to convert numbers to words
def number_to_word(number):
    words = ["ONE", "TWO", "THREE", "FOUR", "FIVE"]
    return words[number - 1]

# Generate 5 sets of keys and addresses
keys_and_addresses = [generate_key_and_address() for _ in range(5)]

# Save the results to an .env file
with open('.env', 'w') as f:
    for i, (key, address) in enumerate(keys_and_addresses, start=1):
        word = number_to_word(i)
        f.write(f"KEY_{word}={key}\n")
        f.write(f"ADDRESS_{word}={address}\n")

print("Keys and addresses have been saved to .env file.")