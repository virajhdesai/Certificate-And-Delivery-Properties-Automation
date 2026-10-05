import sys
import json
import os
from akamai.edgegrid import EdgeGridAuth, EdgeRc
from requests import Session

if len(sys.argv) < 3:
    print("ERROR: Missing arguments. Usage: python check_cps_status.py <enrollment_id> <section>")
    sys.exit(1)

enrollment_id = sys.argv[1]
section = sys.argv[2]
edgerc_path = os.path.expanduser("~/.edgerc")

try:
    edgerc = EdgeRc(edgerc_path)
    baseurl = edgerc.get(section, 'host')
    account_key = edgerc.get(section, 'account_key') if edgerc.has_option(section, 'account_key') else None
    if not account_key and edgerc.has_option(section, 'account_switch_key'):
        account_key = edgerc.get(section, 'account_switch_key')
    
    session = Session()
    session.auth = EdgeGridAuth.from_edgerc(edgerc_path, section)
    
    url = f"https://{baseurl}/cps/v2/enrollments/{enrollment_id}/deployments"
    if account_key:
        url += f"?accountSwitchKey={account_key}"
        
    headers = {"Accept": "application/vnd.akamai.cps.deployments.v7+json"}
    response = session.get(url, headers=headers)
    print(response.text)
except Exception as e:
    print(f"ERROR: {str(e)}")