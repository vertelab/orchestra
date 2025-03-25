import subprocess

file_path = "/var/log/odoo/test-odoo-server.log"

def exstract_tracebacks(log):
    tracebacks = []
    traceback = ""
    split_log = log.split("\n")
    check = False
    for line in split_log:
        if "INFO" in line or "WARNING" in line or "CRITICAL" in line:
            if traceback:
                tracebacks.append(traceback)
            check = False
        elif "Traceback" in line:
            check = True
        if check:
            traceback += line
    return tracebacks

with open(file_path, "r", encoding="utf-8") as file:

    log = file.read()
    warnings = subprocess.run(["grep", "WARNING", file_path], capture_output=True, text=True)
    errors = subprocess.run(["grep", "ERROR", file_path], capture_output=True, text=True)
    criticals = subprocess.run(["grep", "CRITICAL", file_path], capture_output=True, text=True)
    tracebacks = exstract_tracebacks(log)
    report = {"warnings":warnings, "errors": errors, "criticals": criticals, "tracebacks": tracebacks, "full_log": log}
    print(report)
    file.close()
