import argparse
import json

parser = argparse.ArgumentParser()
parser.add_argument("result_file", help="Output from the config test")
args = parser.parse_args()

with open(args.result_file) as result_file:
    results = json.load(result_file)


providers = list(results["summary"].keys())

markdown_table = []
markdown_table.append(
    "| Provider Folder | Provider Status | Configs tested | Successful |"
)
markdown_table.append(
    "| :-------------- | :-------------: | :------------: | :--------: |"
)
for provider in providers:
    configs_tested = results["summary"][provider]["total"]
    configs_success = results["summary"][provider]["success"]
    success_rate = results["summary"][provider]["rate"]
    success_rate_percent = round(success_rate * 100)

    if success_rate_percent == 100:
        emoji = f":100:"
    elif success_rate_percent >= 90:
        emoji = f":white_check_mark: ({success_rate_percent}%)"
    elif success_rate_percent >= 70:
        emoji = f":ok: ({success_rate_percent}%)"
    elif success_rate_percent >= 30:
        emoji = f":warning: ({success_rate_percent}%)"
    else:
        emoji = f":sos: ({success_rate_percent}%)"

    markdown_table.append(
        f"| {provider} | {emoji} | {configs_tested} | {configs_success} |"
    )

for line in markdown_table:
    print(line)
