/* SPDX-License-Identifier: Apache-2.0 */
#include "line_reader.h"

#include <string.h>

void keycap_line_reader_init(struct keycap_line_reader *reader)
{
	memset(reader, 0, sizeof(*reader));
}

void keycap_line_reader_resynchronize(struct keycap_line_reader *reader)
{
	reader->length = 0;
	reader->resynchronizing = true;
}

enum keycap_line_status keycap_line_reader_push(struct keycap_line_reader *reader,
						uint8_t byte)
{
	if (byte == '\n') {
		if (reader->resynchronizing) {
			reader->resynchronizing = false;
			reader->length = 0;
			return KEYCAP_LINE_NONE;
		}
		if (reader->length == 0) {
			return KEYCAP_LINE_NONE;
		}
		reader->line[reader->length] = '\0';
		reader->length = 0;
		return KEYCAP_LINE_READY;
	}

	if (reader->resynchronizing || byte == '\r') {
		return KEYCAP_LINE_NONE;
	}

	if (reader->length + 1 < sizeof(reader->line)) {
		reader->line[reader->length++] = (char)byte;
		return KEYCAP_LINE_NONE;
	}

	keycap_line_reader_resynchronize(reader);
	return KEYCAP_LINE_OVERFLOW;
}
