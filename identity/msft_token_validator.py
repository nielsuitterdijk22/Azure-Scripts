#!/usr/bin/env python3
"""
Microsoft Access Token Validator

This script validates Microsoft access tokens for given scopes and roles.
It decodes JWT tokens, validates signatures against Microsoft's public keys,
and checks if the token contains required scopes and roles.
"""

import base64
import json
import time
from typing import Any, Dict, List, Optional
from urllib.parse import urljoin

import jwt
import requests
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

################
### Jonathan ###
################


def validate_token(token: str) -> bool:
    """
    Validate JWT token for authentication and authorization.

    Returns True if token is valid, False otherwise.
    Logs detailed error information internally but does not expose it to callers.
    """
    try:
        # Get signing key
        jwks_client = jwt.PyJWKClient(
            JWKS_URL, cache_keys=False
        )  # Disable caching to get fresh keys

        signing_key = jwks_client.get_signing_key_from_jwt(token)

        # Verify and decode the token with the public key
        logger.info("Attempting signature verification...")
        decoded = jwt.decode(
            jwt=token,
            key=signing_key.key,
            algorithms=["RS256"],
            audience=AUD,
            issuer=EXPECTED_ISSUER,
            options={
                "verify_signature": True,
                "verify_aud": True,
                "verify_iss": True,
                "verify_nbf": True,
                "verify_exp": True,
                "verify_iat": True,
            },
        )
        logger.info("Token signature verified successfully")

        # --- tenant check ---
        tid = decoded.get("tid")
        if tid != EXPECTED_TENANT_ID:
            logger.warning(f"Token rejected: wrong tenant {tid}")
            return False

        # --- appid check ---
        appid_claim = decoded.get("appid")
        if appid_claim != APPID:
            logger.warning(f"Token rejected: wrong appid {appid_claim}")
            return False

        logger.info("Token accepted")
        return True

    except Exception as e:
        logger.error(f"Token validation failed: {type(e).__name__}: {str(e)}")
        return False


####################
### End Jonathan ###
####################


class MSFTTokenValidator:
    """Microsoft Access Token Validator"""

    def __init__(self, tenant_id: Optional[str] = None):
        """
        Initialize the validator

        Args:
            tenant_id: Azure AD tenant ID (optional, extracted from token if not provided)
        """
        self.tenant_id = tenant_id
        self.jwks_cache = {}
        self.jwks_cache_ttl = 3600  # Cache for 1 hour
        self.jwks_cache_time = {}

    def _get_jwks_uri(self, tenant_id: str) -> str:
        """Get JWKS URI for the tenant"""
        return f"https://login.microsoftonline.com/{tenant_id}/discovery/v2.0/keys"

    def _fetch_jwks(self, tenant_id: str) -> Dict[str, Any]:
        """Fetch JSON Web Key Set from Microsoft"""
        current_time = time.time()

        # Check cache
        if (
            tenant_id in self.jwks_cache
            and tenant_id in self.jwks_cache_time
            and current_time - self.jwks_cache_time[tenant_id] < self.jwks_cache_ttl
        ):
            return self.jwks_cache[tenant_id]

        jwks_uri = self._get_jwks_uri(tenant_id)
        try:
            response = requests.get(jwks_uri, timeout=10)
            response.raise_for_status()
            jwks = response.json()

            # Cache the result
            self.jwks_cache[tenant_id] = jwks
            self.jwks_cache_time[tenant_id] = current_time

            return jwks
        except requests.RequestException as e:
            raise ValueError(f"Failed to fetch JWKS: {e}")

    def _decode_token_header(self, token: str) -> Dict[str, Any]:
        """Decode JWT token header without verification"""
        try:
            header = jwt.get_unverified_header(token)
            return header
        except Exception as e:
            raise ValueError(f"Invalid token format: {e}")

    def _decode_token_payload(self, token: str) -> Dict[str, Any]:
        """Decode JWT token payload without verification"""
        try:
            payload = jwt.decode(token, options={"verify_signature": False})
            return payload
        except Exception as e:
            raise ValueError(f"Invalid token format: {e}")

    def _get_public_key(self, token: str, tenant_id: str) -> Any:
        """Get the public key for token verification"""
        header = self._decode_token_header(token)
        kid = header.get("kid")

        if not kid:
            raise ValueError("Token header missing 'kid' field")

        jwks = self._fetch_jwks(tenant_id)

        for key in jwks.get("keys", []):
            if key.get("kid") == kid:
                return jwt.algorithms.RSAAlgorithm.from_jwk(json.dumps(key))

        raise ValueError(f"No matching key found for kid: {kid}")

    def validate_token_signature(
        self, token: str, tenant_id: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Validate token signature and return decoded payload

        Args:
            token: JWT access token
            tenant_id: Azure AD tenant ID (optional)

        Returns:
            Decoded token payload

        Raises:
            ValueError: If token is invalid
        """
        # Extract tenant ID from token if not provided
        if not tenant_id:
            payload = self._decode_token_payload(token)
            tenant_id = payload.get("tid")
            if not tenant_id:
                raise ValueError("Cannot determine tenant ID from token")

        # Get public key and verify signature
        public_key = self._get_public_key(token, tenant_id)

        try:
            # Verify signature and decode payload
            payload = jwt.decode(
                token,
                public_key,
                algorithms=["RS256"],
                options={
                    "verify_signature": True,
                    "verify_exp": True,
                    "verify_iat": True,
                    "verify_nbf": True,
                },
            )
            return payload
        except jwt.ExpiredSignatureError:
            raise ValueError("Token has expired")
        except jwt.InvalidTokenError as e:
            raise ValueError(f"Invalid token: {e}")

    def validate_scopes(
        self, payload: Dict[str, Any], required_scopes: List[str]
    ) -> bool:
        """
        Validate if token contains required scopes

        Args:
            payload: Decoded token payload
            required_scopes: List of required scopes

        Returns:
            True if all required scopes are present
        """
        token_scopes = payload.get("scp", "").split() if payload.get("scp") else []

        # Also check 'scopes' field (sometimes used instead of 'scp')
        if not token_scopes and "scopes" in payload:
            token_scopes = (
                payload["scopes"]
                if isinstance(payload["scopes"], list)
                else payload["scopes"].split()
            )

        # Check if all required scopes are present
        for scope in required_scopes:
            if scope not in token_scopes:
                return False

        return True

    def validate_roles(
        self, payload: Dict[str, Any], required_roles: List[str]
    ) -> bool:
        """
        Validate if token contains required roles

        Args:
            payload: Decoded token payload
            required_roles: List of required roles

        Returns:
            True if any of the required roles are present
        """
        token_roles = payload.get("roles", [])

        if not isinstance(token_roles, list):
            return False

        # Check if any required role is present
        for role in required_roles:
            if role in token_roles:
                return True

        return False

    def validate_token(
        self,
        token: str,
        required_scopes: Optional[List[str]] = None,
        required_roles: Optional[List[str]] = None,
        tenant_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Validate Microsoft access token for scopes and roles

        Args:
            token: JWT access token
            required_scopes: List of required scopes (optional)
            required_roles: List of required roles (optional)
            tenant_id: Azure AD tenant ID (optional)

        Returns:
            Validation result with payload and validation status

        Raises:
            ValueError: If token validation fails
        """
        # Validate signature and get payload
        payload = self.validate_token_signature(token, tenant_id)

        result = {
            "valid": True,
            "payload": payload,
            "scopes_valid": True,
            "roles_valid": True,
            "errors": [],
        }

        # Validate scopes if required
        if required_scopes:
            if not self.validate_scopes(payload, required_scopes):
                result["valid"] = False
                result["scopes_valid"] = False
                result["errors"].append(f"Missing required scopes: {required_scopes}")

        # Validate roles if required
        if required_roles:
            if not self.validate_roles(payload, required_roles):
                result["valid"] = False
                result["roles_valid"] = False
                result["errors"].append(f"Missing required roles: {required_roles}")

        return result


def main():
    """Example usage of the MSFTTokenValidator"""
    import argparse

    parser = argparse.ArgumentParser(description="Validate Microsoft access token")
    parser.add_argument("token", help="JWT access token to validate")
    parser.add_argument("--scopes", nargs="+", help="Required scopes")
    parser.add_argument("--roles", nargs="+", help="Required roles")
    parser.add_argument("--tenant-id", help="Azure AD tenant ID")

    args = parser.parse_args()

    validator = MSFTTokenValidator(tenant_id=args.tenant_id)

    try:
        result = validator.validate_token(
            token=args.token,
            required_scopes=args.scopes,
            required_roles=args.roles,
            tenant_id=args.tenant_id,
        )

        print(f"Token valid: {result['valid']}")
        print(f"Scopes valid: {result['scopes_valid']}")
        print(f"Roles valid: {result['roles_valid']}")

        if result["errors"]:
            print(f"Errors: {result['errors']}")

        print(f"\nToken payload:")
        print(json.dumps(result["payload"], indent=2))

    except Exception as e:
        print(f"Validation failed: {e}")
        return 1

    return 0


if __name__ == "__main__":
    exit(main())
