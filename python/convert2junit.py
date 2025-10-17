#!/usr/bin/python

import json
import csv
import sys
from datetime import datetime
from collections import defaultdict
from xml.etree.ElementTree import Element, SubElement, ElementTree

def convert_chaos_journal_to_junit(journal_path, junit_path):
    # Load the Chaos Toolkit journal JSON file
    with open(journal_path, 'r') as f:
        journal = json.load(f)

    # Root element of JUnit XML
    testsuites = Element('testsuites')

    # Create a single testsuite element
    testsuite = SubElement(testsuites, 'testsuite')
    testsuite.attrib['name'] = journal.get('experiment', {}).get('title', 'Chaos Toolkit Experiment')

    total_tests = 0
    total_failures = 0
    total_time = 0.0

    # Experiment steps are in "run"
    run_steps = journal.get('run', [])

    for step in run_steps:
        # Get step name
        test_name = step.get('activity', step.get('name', 'unnamed-test'))

        # Calculate duration in seconds (timestamps are usually in milliseconds)
        start_time = step.get('start', 0)
        end_time = step.get('end', 0)
        duration = max(0, end_time - start_time) / 1000

        testcase = SubElement(testsuite, 'testcase')
        testcase.attrib['name'] = test_name
        testcase.attrib['time'] = f"{duration:.3f}"

        # If test status is not 'succeeded', mark as failure
        status = step.get('status', '').lower()
        if status != 'succeeded':
            total_failures += 1
            failure = SubElement(testcase, 'failure')
            failure.attrib['message'] = step.get('description', 'Failure')
            failure.text = step.get('hypothesis', '')

        total_tests += 1
        total_time += duration

    # Set testsuite attributes
    testsuite.attrib['tests'] = str(total_tests)
    testsuite.attrib['failures'] = str(total_failures)
    testsuite.attrib['time'] = f"{total_time:.3f}"

    # Write JUnit XML to file
    tree = ElementTree(testsuites)
    tree.write(junit_path, encoding='utf-8', xml_declaration=True)

    print(f"JUnit XML has been saved to {junit_path}")

def load_test_definition(json_path):
    with open(json_path, 'r', encoding='utf-8') as f:
        test_def = json.load(f)
    services = defaultdict(list)
    perf = test_def.get("test", {}).get("performance", {})
    # If "services" exists, load as before
    if "services" in perf:
        for svc_name, svc in perf["services"].items():
            url = svc["url"]
            services[url].append({
                "indicator": svc["indicator"],
                "sla": float(svc["sla"])
            })
    return services


def analyze_jmeter_csv(csv_file_path, services):
    grouped = defaultdict(lambda: {
        "total_time_ms": 0.0,
        "failures": 0,
        "count": 0,
        "label": "",
        "failures_set": set()
    })

    # Read CSV and group by label (which should be the URL)
    with open(csv_file_path, 'r', newline='', encoding='utf-8') as csvfile:
        reader = csv.DictReader(csvfile)
        for row in reader:
            label = row.get("label", "Unnamed")
            success = row.get("success", "true").lower() == "true"
            time_ms = float(row.get("elapsed", "0"))
            grouped[label]["total_time_ms"] += time_ms
            grouped[label]["count"] += 1
            grouped[label]["label"] = label
            if not success:
                grouped[label]["failures"] += 1
                grouped[label]["failures_set"].add(
                    (row.get("responseCode", "Error"), row.get("responseMessage", "No message"))
                )

    return grouped

def convert_jmeter_csv_with_sla(csv_file_path, test_definition_path, junit_output_path):
    services = load_test_definition(test_definition_path)
    grouped = analyze_jmeter_csv(csv_file_path, services)

    testsuite = Element("testsuite")
    testsuite.set("name", "JMeter Results with SLA Evaluation")
    testsuite.set("timestamp", datetime.now().isoformat())

    total = 0
    failures = 0

    for label, data in grouped.items():
        # Find matching SLA definitions by label (URL)
        sla_defs = services.get(label, [])
        # If no match or services structure missing, use default SLA: 10 pct_errors
        if not sla_defs:
            sla_defs = [{"indicator": "pct_errors", "sla": 10.0}]

        total_calls = data["count"]
        total_time_ms = data["total_time_ms"]
        failure_count = data["failures"]
        avg_time = total_time_ms / total_calls if total_calls else 0
        pct_errors = (100 * failure_count / total_calls) if total_calls else 0

        testcase = SubElement(testsuite, "testcase")
        testcase.set("name", label)
        testcase.set("classname", "JMeter")
        testcase.set("time", f"{total_time_ms / 1000:.3f}")

        sla_failures = []
        for sla_def in sla_defs:
            indicator = sla_def["indicator"]
            sla = sla_def["sla"]
            fail_reason = None
            if indicator == "pct_errors":
                if pct_errors > sla:
                    fail_reason = f"Error percentage {pct_errors:.2f}% exceeds SLA {sla}%"
            elif indicator == "requests":
                if total_calls < sla:
                    fail_reason = f"Total requests {total_calls} is below SLA {sla}"
            elif indicator == "response_time":
                if avg_time > sla:
                    fail_reason = f"Average response time {avg_time:.2f}ms exceeds SLA {sla}ms"
            if fail_reason:
                sla_failures.append(fail_reason)

        if sla_failures:
            failures += 1
            failure = SubElement(testcase, "failure")
            failure.set("message", " | ".join(sla_failures))
            failure.text = "\n".join(
                f"{code}: {msg}" for code, msg in data["failures_set"]
            )

        sysout = SubElement(testcase, "system-out")
        if sla_defs and len(sla_defs) > 0:
            sla_checked = ', '.join([f"{s['indicator']}={s['sla']}" for s in sla_defs])
        else:
            sla_checked = "pct_errors=10.0"
        sysout.text = (
            f"Total Calls: {total_calls}\n"
            f"Failures: {failure_count}\n"
            f"Error Percentage: {pct_errors:.2f}%\n"
            f"Average Duration: {avg_time:.2f} ms\n"
            f"SLAs checked: {sla_checked}\n"
        )
        total += 1

    testsuite.set("tests", str(total))
    testsuite.set("failures", str(failures))
    testsuite.set("errors", "0")
    testsuite.set("skipped", "0")

    tree = ElementTree(testsuite)
    tree.write(junit_output_path, encoding="utf-8", xml_declaration=True)
    print(f"JUnit XML written to: {junit_output_path}")

if __name__ == "__main__":
    if len(sys.argv) != 5:
        print("Usage: ./convert2junit.py [json|csv] <input_file> <test_definition.json> <output_junit.xml>")
        sys.exit(1)

    if sys.argv[1] == 'json':
        convert_chaos_journal_to_junit(sys.argv[2], sys.argv[4])
    elif sys.argv[1] == 'csv':
        convert_jmeter_csv_with_sla(sys.argv[2], sys.argv[3], sys.argv[4])
    else:
        print(f"Unsupported format: {sys.argv[1]}")
        print("Only json or csv formats are supported.")
        sys.exit(1)
