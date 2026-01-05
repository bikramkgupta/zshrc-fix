#!/bin/bash
input=$(cat)

# Extract data
MODEL=$(echo "$input" | jq -r '.model.display_name')
CONTEXT_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size')
USAGE=$(echo "$input" | jq '.context_window.current_usage')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
CURRENT_DIR=$(echo "$input" | jq -r '.workspace.current_dir')

if [ "$USAGE" != "null" ]; then
    # Get individual token counts
    INPUT_TOKENS=$(echo "$USAGE" | jq -r '.input_tokens')
    OUTPUT_TOKENS=$(echo "$USAGE" | jq -r '.output_tokens')
    CACHE_CREATE=$(echo "$USAGE" | jq -r '.cache_creation_input_tokens')
    CACHE_READ=$(echo "$USAGE" | jq -r '.cache_read_input_tokens')

    # Total current context
    CURRENT_TOKENS=$(echo "$USAGE" | jq '.input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens')
    PERCENT_USED=$((CURRENT_TOKENS * 100 / CONTEXT_SIZE))

    # Format in K for readability
    CURRENT_K=$((CURRENT_TOKENS / 1000))
    CONTEXT_K=$((CONTEXT_SIZE / 1000))
    OUTPUT_K=$((OUTPUT_TOKENS / 1000))
    CACHE_READ_K=$((CACHE_READ / 1000))

    # Truncate directory path
    DIR=$(basename "$CURRENT_DIR")

    # Build statusline with useful info
    echo "[$MODEL] ${CURRENT_K}K/${CONTEXT_K}K (${PERCENT_USED}%) | ${CACHE_READ_K}K cached | ${OUTPUT_K}K out | \$${COST}"
else
    DIR=$(basename "$CURRENT_DIR")
    echo "[$MODEL] Context: 0% | $DIR"
fi
