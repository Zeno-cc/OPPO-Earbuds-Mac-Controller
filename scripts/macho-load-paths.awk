# Extract only the indented dependency rows produced by `otool -L`.
# Do not treat the input binary's absolute path (or per-architecture headers)
# as a load command. Preserve spaces in real library paths for validation.
/^[[:space:]]+.* \(compatibility version [0-9]/ {
    sub(/^[[:space:]]+/, "")
    sub(/ \(compatibility version [0-9].*$/, "")
    print
}
