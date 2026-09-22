/^\t/ {
    line = $0
    sub(/^\t+/, "", line)
    sub(/ \(compatibility version.*$/, "", line)
    sub(/ \(current version.*$/, "", line)
    if (line != "") print line
}
