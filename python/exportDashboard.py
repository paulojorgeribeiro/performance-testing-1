import requests
import json
import logging
import os
from configuration import user_key, dashboard_guid

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

def get_dashboard_page_guid(key, dashboard_guid):
    query = """
    {
      actor {
        entity(guid: "%s") {
          ... on DashboardEntity {
            guid
            name
            pages {
              guid
              name
            }
          }
        }
      }
    }
    """ % dashboard_guid
    
    endpoint = "https://api.newrelic.com/graphql"
    headers = {'API-Key': f'{key}'}
    response = requests.post(endpoint, headers=headers, json={"query": query}, verify=False)
    
    if response.status_code == 200:
        json_dictionary = json.loads(response.content)
        pages = json_dictionary["data"]["actor"]["entity"]["pages"]
        if pages:
            return pages[0]["guid"]  # Return the GUID of the first page
        else:
            logging.error("No pages found in the dashboard.")
            raise Exception("No pages found in the dashboard.")
    else:
        logging.error(f'Failed to fetch dashboard pages with status code {response.status_code}.')
        raise Exception(f'Failed to fetch dashboard pages with status code {response.status_code}.')

def nerdgraph_dashboards(key, page_guid):
    query = """
    mutation {
      dashboardCreateSnapshotUrl(guid: "%s")
    }
    """ % page_guid
    
    endpoint = "https://api.newrelic.com/graphql"
    headers = {'API-Key': f'{key}'}
    response = requests.post(endpoint, headers=headers, json={"query": query}, verify=False)

    if response.status_code == 200:
        json_dictionary = json.loads(response.content)
        if "data" in json_dictionary and json_dictionary["data"]["dashboardCreateSnapshotUrl"]:
            url_pdf = json_dictionary["data"]["dashboardCreateSnapshotUrl"]
            logging.info(f'Snapshot URL: {url_pdf}')

            # Download and save the PDF file
            dashboard_response = requests.get(url_pdf, stream=True, verify=False)
            with open('Test-Execution-Dashboard.pdf', 'wb') as file:
                file.write(dashboard_response.content)
            logging.info('Dashboard PDF saved successfully.')
        else:
            logging.error(f"Error in response: {json_dictionary}")
            raise Exception("Failed to create snapshot URL.")
    else:
        logging.error(f"Error in response: {response.content}")
        raise Exception(f'Nerdgraph query failed with status code {response.status_code}.')

if __name__ == "__main__":
    try:
        page_guid = get_dashboard_page_guid(user_key, dashboard_guid)
        nerdgraph_dashboards(user_key, page_guid)
    except Exception as e:
        logging.error(f'An error occurred: {e}')
