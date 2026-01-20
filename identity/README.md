# Microsoft Access Token Validator

A Python script that validates Microsoft access tokens for given scopes and roles.

## Features

- Validates JWT signature against Microsoft's public keys
- Checks token expiration and other standard JWT claims
- Validates required scopes and roles
- Caches JWKS for performance
- Command-line interface for easy testing

## Installation

```bash
pip install -r requirements.txt
```

## Usage

### Command Line

```bash
# Basic validation
python msft_token_validator.py "your_jwt_token_here"

# Validate with required scopes
python msft_token_validator.py "token" --scopes "User.Read" "Mail.Read"

# Validate with required roles
python msft_token_validator.py "token" --roles "Admin" "User"

# Validate with specific tenant ID
python msft_token_validator.py "token" --tenant-id "your-tenant-id"
```

### Programmatic Usage

```python
from msft_token_validator import MSFTTokenValidator

# Initialize validator
validator = MSFTTokenValidator()

# Validate token
result = validator.validate_token(
    token="your_jwt_token",
    required_scopes=["User.Read", "Mail.Read"],
    required_roles=["Admin"]
)

if result['valid']:
    print("Token is valid!")
    print(f"User: {result['payload'].get('name')}")
else:
    print(f"Validation failed: {result['errors']}")
```

## Token Payload

The validator returns the full decoded token payload, which typically includes:

- `aud`: Audience
- `iss`: Issuer
- `exp`: Expiration time
- `iat`: Issued at time
- `tid`: Tenant ID
- `scp`: Scopes (space-separated)
- `roles`: Roles array
- `name`: User name
- `upn`: User principal name

## Error Handling

The validator handles various error conditions:

- Invalid token format
- Expired tokens
- Invalid signatures
- Missing required scopes or roles
- Network errors when fetching public keys