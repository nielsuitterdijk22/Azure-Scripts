#!/usr/bin/env python3

import argparse
import sys
from azure.identity import DefaultAzureCredential
from azure.mgmt.privatedns import PrivateDnsManagementClient
from azure.mgmt.privatedns.models import RecordSet, ARecord

def get_dns_client(subscription_id):
    """Create DNS management client for given subscription"""
    credential = DefaultAzureCredential()
    return PrivateDnsManagementClient(credential, subscription_id)

def get_zone_records(dns_client, resource_group, zone_name):
    """Fetch A records from a DNS zone"""
    records = []
    try:
        for record in dns_client.record_sets.list(resource_group_name=resource_group, private_zone_name=zone_name):
            if record.name != "@" and record.a_records:  # Only A records
                records.append(record)
        return True, records
    except Exception as e:
        print(f"Error fetching records from zone {zone_name}: {e}")
        return False, []

def copy_record(dns_client, target_rg, target_zone, record):
    """Copy a single A record to target zone"""
    try:
        record_set = RecordSet()
        record_set.ttl = record.ttl or 3600
        record_set.a_records = record.a_records

        dns_client.record_sets.create_or_update(
            resource_group_name=target_rg,
            private_zone_name=target_zone,
            record_type='A',
            relative_record_set_name=record.name,
            parameters=record_set
        )
        ip_addresses = [a.ipv4_address for a in record.a_records]
        print(f"✓ Copied A record: {record.name} -> {', '.join(ip_addresses)}")
        return True

    except Exception as e:
        print(f"✗ Failed to copy A record {record.name}: {e}")
        return False

def copy_dns_zone(source_sub, source_rg, source_zone, target_sub, target_rg, target_zone, dry_run=False):
    """Copy all A records from source zone to target zone"""

    print(f"Source: {source_zone} (Sub: {source_sub}, RG: {source_rg})")
    print(f"Target: {target_zone} (Sub: {target_sub}, RG: {target_rg})")
    print(f"Dry run: {dry_run}")
    print("-" * 50)

    # Create DNS clients
    source_client = get_dns_client(source_sub)
    target_client = get_dns_client(target_sub) if target_sub != source_sub else source_client

    # Get source A records
    print("Fetching source A records...")
    success, source_records = get_zone_records(source_client, source_rg, source_zone)

    if not success:
        print("Failed to fetch records from source zone")
        return False

    if not source_records:
        print("No A records found in source zone")
        return True

    print(f"Found {len(source_records)} A records to copy")

    if dry_run:
        print("\nDRY RUN - A records that would be copied:")
        for record in source_records:
            ip_addresses = [a.ipv4_address for a in record.a_records]
            print(f"  A: {record.name} -> {', '.join(ip_addresses)}")
        return True

    # Copy A records
    print("\nCopying A records...")
    success_count = 0

    for record in source_records:
        if copy_record(target_client, target_rg, target_zone, record):
            success_count += 1

    print(f"\nCompleted: {success_count}/{len(source_records)} A records copied successfully")
    return success_count == len(source_records)

def main():
    parser = argparse.ArgumentParser(description='Copy A records between Azure private DNS zones')
    parser.add_argument('--source-sub', required=True, help='Source subscription ID')
    parser.add_argument('--source-rg', required=True, help='Source resource group name')
    parser.add_argument('--source-zone', required=True, help='Source DNS zone name')
    parser.add_argument('--target-sub', required=True, help='Target subscription ID')
    parser.add_argument('--target-rg', required=True, help='Target resource group name')
    parser.add_argument('--target-zone', required=True, help='Target DNS zone name')
    parser.add_argument('--dry-run', action='store_true', help='Show what would be copied without making changes')

    args = parser.parse_args()

    try:
        success = copy_dns_zone(
            args.source_sub, args.source_rg, args.source_zone,
            args.target_sub, args.target_rg, args.target_zone,
            args.dry_run
        )

        sys.exit(0 if success else 1)

    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()