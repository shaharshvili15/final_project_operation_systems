# 1. Build the expected output: numbers 1–100, then <END>
expected=$(for i in $(seq 1 100); do
    printf "%s\n" "$i"
done)
expected+=$'<END>\n'

# 2. Run your analyzer with the same input and capture its output
actual=$(seq 1 100 | ./output/analyzer 10 output/logger)

# 3. Compare the two outputs
if [ "$expected" = "$actual" ]; then
    echo "✅ Test passed: lines 1–100 in same order"
else
    echo "❌ Test failed: output does not match expected"
    echo "---- Expected ----"
    printf "%s" "$expected"
    echo "---- Actual ----"
    printf "%s" "$actual"
fi
