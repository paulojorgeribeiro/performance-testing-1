#!/usr/bin/env bash
set -euo pipefail

LAC_ID="${1:?usage: report-summary.sh <LAC_ID> <TEST_ID> [OUT_DIR]}"
TEST_ID="${2:?usage: report-summary.sh <LAC_ID> <TEST_ID> [OUT_DIR]}"
OUT_DIR="${3:-results}"
RAW_DIR="${OUT_DIR}/raw"
SUMMARY="${OUT_DIR}/summary.json"

mkdir -p "${RAW_DIR}"

# FONTE DE DADOS:
# 1) Se existir CSV do JMeter em ${RAW_DIR}/*.csv com colunas (timestamp_ms, elapsed_ms, success),
#    o script calcula métricas automaticamente.
# 2) Caso contrário, usa variáveis de ambiente pré-calculadas:
#    THROUGHPUT_RPS, P95_MS, AVG_MS, ERROR_PCT, DURATION_S, REQUESTS_TOTAL

CSV="$(ls "${RAW_DIR}"/*.csv 2>/dev/null | head -n1 || true)"

throughput_rps="${THROUGHPUT_RPS:-0}"
p95_latency_ms="${P95_MS:-0}"
avg_latency_ms="${AVG_MS:-0}"
error_rate_pct="${ERROR_PCT:-0}"
duration_s="${DURATION_S:-0}"
requests_total="${REQUESTS_TOTAL:-0}"

if [[ -n "$CSV" ]]; then
  # pedidos totais (assume header na primeira linha)
  requests_total=$(($(wc -l < "$CSV") - 1))
  # duração (s) via min/max timestamp (ms)
  duration_s=$(awk -F, 'NR>1{if(min==""||$1<min){min=$1}; if($1>max){max=$1}} END{d=int((max-min)/1000); if(d<1)d=1; print d}' "$CSV")
  # média de latência
  avg_latency_ms=$(awk -F, 'NR>1{s+=$2; c+=1} END{if(c>0) printf "%.2f", s/c; else print 0}' "$CSV")
  # p95 de latência
  p95_latency_ms=$(awk -F, 'NR>1{print $2}' "$CSV" | sort -n | awk 'BEGIN{p=0.95} {a[NR]=$1} END{i=int(p*NR); if(i<1)i=NR; print a[i]+0}')
  # erros
  errors=$(awk -F, 'NR>1 && $3=="false"{e+=1} END{print e+0}' "$CSV")
  error_rate_pct=$(awk -v e="${errors:-0}" -v t="${requests_total:-1}" 'BEGIN{printf "%.3f", (e*100.0)/t}')
  throughput_rps=$(awk -v t="${requests_total:-0}" -v d="${duration_s:-1}" 'BEGIN{printf "%.2f", t/d}')
fi

timestamp_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

cat > "${SUMMARY}" <<JSON
{
  "lac_id": "${LAC_ID}",
  "test_id": "${TEST_ID}",
  "timestamp_utc": "${timestamp_utc}",
  "tool": "jmeter",
  "version": "1.0",
  "metrics": {
    "throughput_rps": ${throughput_rps},
    "avg_latency_ms": ${avg_latency_ms},
    "p95_latency_ms": ${p95_latency_ms},
    "error_rate_pct": ${error_rate_pct},
    "duration_s": ${duration_s},
    "requests_total": ${requests_total}
  },
  "labels": {
    "environment": "${LABEL_ENV:-}",
    "system": "${LABEL_SYS:-}",
    "notes": "${LABEL_NOTES:-}"
  },
  "base_url": "${BASE_URL:-}"
}
JSON

echo "[OK] summary: ${SUMMARY}"
