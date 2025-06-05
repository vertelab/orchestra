import requests, json, sys

file_path = "/var/log/odoo/test-odoo-server.log"
args = sys.argv[1:]
name = ""
branch = ""
is_success = ""
ci_id = ""
return_url = ""
try:
    name = args[0]
    branch = args[1]
    ip = args[2]
    is_success = args[3]
    ci_id = args[4]
    return_url = args[5]
except:
    pass

def extract_tracebacks(split_log):
    tracebacks = []
    traceback = ""
    split_log = log.split("\n")
    check = False
    for line in split_log:
        if "INFO" in line or "WARNING" in line or "CRITICAL" in line:
            if traceback and check:
                tracebacks.append(traceback)
                traceback=""
            check = False
        elif "Traceback" in line:
            check = True
        if check:
            traceback += line
    return tracebacks

def extract_on_message(split_log, extract_message):
    messages = []
    for line in split_log:
        if extract_message in line:
            messages.append(line.strip())
    return messages

def create_local_report(report):
    with open("./json_report.txt", "w+", encoding="utf-8") as file:
        file.write(report)

with open(file_path, "r", encoding="utf-8") as file:

    log = file.read()
    split_log = log.split("\n")
    warnings = extract_on_message(split_log,"WARNING")
    errors = extract_on_message(split_log, "ERROR")
    criticals = extract_on_message(split_log, "CRITICAL")
    tracebacks = extract_tracebacks(split_log)
    report = {"id":ci_id, "name":name, "warnings":warnings, "errors": errors, "criticals": criticals, "tracebacks": tracebacks, "ip_address":ip, "branch": branch, "is_success":is_success, "full_log": log}
    json_report = json.dumps(report)

    if return_url:
        headers = {
        'Content-Type': 'application/json'
        }
        try:
            requests.post(f"{return_url}/project/ci/report",data=json_report,headers=headers)
        except Exception as e:
            print(f"{e=}")
            
    create_local_report(json_report)
