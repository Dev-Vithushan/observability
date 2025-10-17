#!/usr/bin/env python3
'''
Example usage:
    AZURE_CLIENT_ID=XXXXXXXXXXXX AZURE_TENANT_ID=XXXXXXXXXXXX AZURE_CLIENT_SECRET="XXXXXXXXXXXX" python3 amr_resource_discovery.py
TO BE REMOVED FROM THE PRODUCTION CODE
'''
import os
import sys
import json
import yaml
import argparse
import asyncio
from typing import List, Dict, Any, Optional
from dataclasses import dataclass, asdict
from datetime import datetime
import concurrent.futures

try:
    from azure.identity import ClientSecretCredential
    from azure.mgmt.subscription import SubscriptionClient
    from azure.mgmt.resource import ResourceManagementClient
    from azure.core.exceptions import AzureError
    from tabulate import tabulate
except ImportError as e:
    print(f"Error: Missing required dependencies. Please install them:")
    print("pip install azure-identity azure-mgmt-subscription azure-mgmt-resource tabulate pyyaml")
    sys.exit(1)

@dataclass
class AMRResource:
    subscription_id: str
    subscription_name: str
    resource_group: str
    resource_name: str
    resource_id: str
    location: str
    resource_type: str
    provisioning_state: Optional[str] = None
    redis_version: Optional[str] = None
    tags: Optional[Dict[str, str]] = None
    created_date: Optional[str] = None

# --- CONFIG BLOCK (GLOBAL) ---
config = {
    'AZURE_CLIENT_ID': os.getenv("AZURE_CLIENT_ID", "60f4fc60-0b9a-4911-9dca-04440a1cf8d7"),
    'AZURE_TENANT_ID': os.getenv("AZURE_TENANT_ID", "2c03f75f-06e4-46f7-86f5-d8d70bef1cf3"),
    'AZURE_CLIENT_SECRET': os.getenv("AZURE_CLIENT_SECRET"),
    'AZURE_SUBSCRIPTION_FILTER': os.getenv("AZURE_SUBSCRIPTION_FILTER"),
    'MAX_WORKERS': 8,
    'DEBUG': False,
}

class AMRResourceDiscovery:
    def __init__(self, debug: bool = True, max_workers: int = 4, config: dict = None, quiet: bool = False):
        self.credential = None
        self.subscription_client = None
        self.amr_resources = []
        self.debug = debug
        self.quiet = quiet
        self.max_workers = max_workers
        self.config = config if config is not None else {}
        self.client_id = self.config.get('AZURE_CLIENT_ID')
        self.tenant_id = self.config.get('AZURE_TENANT_ID')
        self.client_secret = self.config.get('AZURE_CLIENT_SECRET')
        subscription_filter = self.config.get('AZURE_SUBSCRIPTION_FILTER')
        self.subscription_filter = None
        if subscription_filter:
            self.subscription_filter = [s.strip() for s in subscription_filter.split(",")]

    def authenticate(self) -> bool:
        if not self.client_secret:
            print("ERROR: AZURE_CLIENT_SECRET environment variable is required")
            return False
        try:
            self.credential = ClientSecretCredential(
                tenant_id=self.tenant_id,
                client_id=self.client_id,
                client_secret=self.client_secret
            )
            # Test authentication by getting subscriptions
            self.subscription_client = SubscriptionClient(self.credential)
            if self.debug and not self.quiet:
                print(f"Successfully authenticated with service principal: {self.client_id}")
            return True
        except AzureError as e:
            print(f"ERROR: Authentication failed: {e}")
            return False

    def discover_subscriptions(self) -> List[Dict[str, str]]:
        subscriptions = []
        try:
            if self.debug and not self.quiet:
                print("Discovering accessible subscriptions...")
            for subscription in self.subscription_client.subscriptions.list():
                # Apply subscription filter if provided
                if self.subscription_filter and subscription.subscription_id not in self.subscription_filter:
                    continue
                subscriptions.append({
                    'id': subscription.subscription_id,
                    'name': subscription.display_name or 'Unknown',
                    'state': subscription.state or 'Unknown'
                })
            if self.debug and not self.quiet:
                print(f"Found {len(subscriptions)} accessible subscriptions")
        except AzureError as e:
            print(f"ERROR: Failed to discover subscriptions: {e}")
        return subscriptions

    def discover_amr_resources_in_subscription(self, subscription: Dict[str, str]) -> List[AMRResource]:
        amr_resources = []
        try:
            resource_client = ResourceManagementClient(self.credential, subscription['id'])
            # Filter for Microsoft.Cache/Redis and Microsoft.Cache/redisEnterprise resources
            # redis_filter = "resourceType eq 'Microsoft.Cache/Redis' or resourceType eq 'Microsoft.Cache/redisEnterprise'"
            redis_filter = "resourceType eq 'Microsoft.Cache/redisEnterprise'"
            for resource in resource_client.resources.list(filter=redis_filter):
                amr_resource = AMRResource(
                    subscription_id=subscription['id'],
                    subscription_name=subscription['name'],
                    resource_group=resource.id.split('/')[4],  # Extract RG from resource ID
                    resource_name=resource.name,
                    resource_id=resource.id,
                    location=resource.location,
                    resource_type=resource.type,
                    tags=resource.tags or {}
                )
                if hasattr(resource, 'properties') and resource.properties:
                    amr_resource.provisioning_state = resource.properties.get('provisioningState')
                    amr_resource.redis_version = resource.properties.get('redisVersion')
                amr_resources.append(amr_resource)
            if self.debug and not self.quiet:
                if amr_resources:
                    print(f"  Found {len(amr_resources)} AMR resources in {subscription['name']}")
                else:
                    print(f"  No AMR resources found in {subscription['name']}")
        except AzureError as e:
            if not self.quiet:
                print(f"  Failed to query subscription {subscription['name']}: {e}")
        return amr_resources

    def discover_all_amr_resources(self) -> bool:
        import time
        start_time = time.time()
        if not self.quiet:
            print(f"\nStarting AMR Resource Discovery")
            print(f"Service Principal: {self.client_id}")
            print(f"Tenant: {self.tenant_id}")

        if not self.authenticate():
            return False

        subscriptions = self.discover_subscriptions()
        if not subscriptions:
            print("ERROR: No subscriptions found")
            return False

        if not self.quiet:
            print(f"\nScanning {len(subscriptions)} subscriptions for AMR resources...")
        total = len(subscriptions)
        results = [None] * total
        def scan_subscription(idx_sub):
            idx, subscription = idx_sub
            if self.debug and not self.quiet:
                print(f"Scanning: {subscription['name']} ({subscription['id']})")
            return self.discover_amr_resources_in_subscription(subscription)

        with concurrent.futures.ThreadPoolExecutor(max_workers=self.max_workers) as executor:
            future_to_idx = {executor.submit(scan_subscription, (idx, sub)): idx for idx, sub in enumerate(subscriptions)}
            for future in concurrent.futures.as_completed(future_to_idx):
                idx = future_to_idx[future]
                try:
                    results[idx] = future.result()
                except Exception as exc:
                    if not self.quiet:
                        print(f"Error scanning subscription {subscriptions[idx]['name']}: {exc}")
        if not self.quiet:
            print()
        for resources in results:
            self.amr_resources.extend(resources)

        elapsed = time.time() - start_time
        if not self.quiet:
            print(f"\nDiscovery completed!")
            print(f"Total AMR resources found: {len(self.amr_resources)}")

        # Debug summary: print all scanned subscriptions and statistics
        if self.debug and not self.quiet:
            print("\n[DEBUG] Subscriptions scanned (summary):")
            for sub in subscriptions:
                print(f"  - {sub['name']} ({sub['id']})")
            print(f"\n[DEBUG] Statistics:")
            print(f"  Number of workers used: {self.max_workers}")
            print(f"  Elapsed time: {elapsed:.2f} seconds")

        return True

    def get_summary_stats(self) -> Dict[str, Any]:
        stats = {
            'total_resources': len(self.amr_resources),
            'subscriptions_with_resources': len(set(r.subscription_id for r in self.amr_resources)),
            'locations': list(set(r.location for r in self.amr_resources)),
            'resource_types': {},
            'provisioning_states': {}
        }
        
        for resource in self.amr_resources:
            # Count by resource type
            stats['resource_types'][resource.resource_type] = stats['resource_types'].get(resource.resource_type, 0) + 1
            # Count by provisioning state
            if resource.provisioning_state:
                stats['provisioning_states'][resource.provisioning_state] = stats['provisioning_states'].get(resource.provisioning_state, 0) + 1
                
        return stats

    def output_results(self, format_type: str = 'table'):
        if self.debug:
            scanned_subs = {(r.subscription_id, r.subscription_name) for r in self.amr_resources}
            print("\n[DEBUG] Subscriptions scanned:")
            for sub_id, sub_name in sorted(scanned_subs):
                print(f"  - {sub_name} ({sub_id})")
        """Output the discovered AMR resources in specified format"""
        if not self.amr_resources:
            print("No AMR resources found to output.")
            return
        timestamp = datetime.now().isoformat()
        if format_type == 'json':
            output_data = {
                'discovery_timestamp': timestamp,
                'summary': self.get_summary_stats(),
                'resources': [asdict(resource) for resource in self.amr_resources]
            }
            print(json.dumps(output_data, indent=2))
        elif format_type == 'yaml':
            output_data = {
                'discovery_timestamp': timestamp,
                'summary': self.get_summary_stats(),
                'resources': [asdict(resource) for resource in self.amr_resources]
            }
            print(yaml.dump(output_data, default_flow_style=False, indent=2))
        elif format_type == 'table':
            # Summary table
            stats = self.get_summary_stats()
            print(f"\nAMR Resource Discovery Details (Generated: {timestamp})")
            print(f"=" * 70)
            print(f"Total Resources Found: {stats['total_resources']}")
            print(f"Subscriptions with AMR: {stats['subscriptions_with_resources']}")
            print(f"Locations: {', '.join(stats['locations'])}")
            if stats['resource_types']:
                print(f"\nResource Types:")
                for rtype, count in stats['resource_types'].items():
                    print(f"  {rtype}: {count}")
            # Detailed table (only Subscription Name, Subscription ID, Resource Name, Resource Type)
            table_data = []
            for resource in self.amr_resources:
                table_data.append([
                    resource.subscription_name[:20] + '...' if len(resource.subscription_name) > 20 else resource.subscription_name,
                    resource.subscription_id,
                    resource.resource_name,
                    resource.resource_type.split('/')[-1]  # Just the resource type name
                ])
            headers = ['Subscription', 'Subscription ID', 'Resource Name', 'Type']
            print(f"\nDetailed AMR Resources:")
            print(tabulate(table_data, headers=headers, tablefmt='grid'))

def main():
    """Main function"""
    parser = argparse.ArgumentParser(
        description="Discover AMR (Azure Cache for Redis) resources across Azure subscriptions",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python amr_resource_discovery.py
  python amr_resource_discovery.py --output-format json
  python amr_resource_discovery.py --output-format yaml

Environment Variables:
  AZURE_CLIENT_SECRET=your_service_principal_secret (Required)
  AZURE_SUBSCRIPTION_FILTER=sub1,sub2,sub3 (Optional - filter specific subscriptions)
        """
    )

    parser.add_argument(
        '--output-format',
        choices=['json', 'yaml', 'table'],
        default='table',
        help='Output format (default: table)'
    )

    parser.add_argument(
        '--debug',
        action='store_true',
        default=False,
        help='Enable debug/diagnostic output (default: False)'
    )
    parser.add_argument(
        '--quiet',
        action='store_true',
        default=True,
        help='Enable quiet mode (default: True)'
    )
    parser.add_argument(
        '--max-workers',
        type=int,
        default=config['MAX_WORKERS'],
        help='Number of parallel threads for scanning subscriptions (default: from config block)'
    )

    args = parser.parse_args()

    quiet_mode = args.quiet and not args.debug
    discovery = AMRResourceDiscovery(debug=args.debug, max_workers=args.max_workers, config=config, quiet=quiet_mode)

    try:
        if discovery.discover_all_amr_resources():
            if quiet_mode:
                # Print only a comma-separated list of unique subscription IDs with AMR resources
                subids_with_resources = sorted({r.subscription_id for r in discovery.amr_resources})
                print(','.join(subids_with_resources))
            else:
                discovery.output_results(args.output_format)
        else:
            print("ERROR: Discovery failed.")
            sys.exit(1)
    except Exception as e:
        print(f"ERROR: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
