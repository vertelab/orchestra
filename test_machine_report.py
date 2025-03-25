file_path = "/var/log/odoo/test-odoo-server.log"

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
            messages.append(line)
    return messages

with open(file_path, "r", encoding="utf-8") as file:

    log = file.read()
    split_log = log.split("\n")
    warnings = extract_on_message(split_log,"WARNING")
    errors = extract_on_message(split_log, "ERROR")
    criticals = extract_on_message(split_log, "CRITICAL")
    tracebacks = extract_tracebacks(split_log)
    report = {"warnings":warnings, "errors": errors, "criticals": criticals, "tracebacks": tracebacks, "full_log": log}
    print(report)
    file.close()
