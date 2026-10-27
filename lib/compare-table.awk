# UTF-8 终端表格：按显示宽度对齐，宽字符不截断在字节中间。无需宿主机 Python。
BEGIN {
    FS = "\t"
    for (i = 1; i < 256; i++) byte[sprintf("%c", i)] = i
    if (columns < 60) columns = 60
    if (columns > 120) columns = 120
    label_width = 12
    result_width = 12
    value_width = int((columns - label_width - result_width - 6) / 2)
}
function decode(text, position,    first, count, point, j) {
    first = byte[substr(text, position, 1)]
    count = 1
    point = first
    if (first >= 240) { count = 4; point = first - 240 }
    else if (first >= 224) { count = 3; point = first - 224 }
    else if (first >= 192) { count = 2; point = first - 192 }
    for (j = 1; j < count; j++) point = point * 64 + byte[substr(text, position + j, 1)] - 128
    char_bytes = count
    char_width = 1
    if ((point >= 768 && point <= 879) || (point >= 65024 && point <= 65039)) char_width = 0
    else if ((point >= 4352 && point <= 4607) || (point >= 11904 && point <= 42191) ||
             (point >= 44032 && point <= 55203) || (point >= 63744 && point <= 64255) ||
             (point >= 65040 && point <= 65131) || (point >= 65281 && point <= 65376) ||
             (point >= 65504 && point <= 65510) || point >= 127744) char_width = 2
}
function cell(text, limit,    position, used, out, tail) {
    position = 1
    used = 0
    out = ""
    while (position <= length(text)) {
        decode(text, position)
        tail = position + char_bytes <= length(text)
        if (used + char_width > limit || (tail && used + char_width > limit - 1)) {
            out = out "…"
            used++
            break
        }
        out = out substr(text, position, char_bytes)
        used += char_width
        position += char_bytes
    }
    while (used++ < limit) out = out " "
    return out
}
{
    print cell($1, label_width) "  " cell($2, value_width) "  " cell($3, value_width) "  " $4
    if (NR == 1) {
        line = ""
        for (i = 0; i < columns; i++) line = line "─"
        print line
    }
}
