/* SPDX-License-Identifier: Apache-2.0 */
#ifndef KEYCAP_LINE_READER_H
#define KEYCAP_LINE_READER_H

#include "protocol.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

enum keycap_line_status {
	/* The byte was consumed and no complete line is available yet. */
	KEYCAP_LINE_NONE,
	/* A complete, NUL-terminated command is available in reader->line. */
	KEYCAP_LINE_READY,
	/* The command exceeded the line buffer. The reader now discards bytes
	 * until the next newline so the tail cannot be read as a command.
	 */
	KEYCAP_LINE_OVERFLOW,
};

struct keycap_line_reader {
	char line[KEYCAP_LINE_MAX];
	size_t length;
	bool resynchronizing;
};

void keycap_line_reader_init(struct keycap_line_reader *reader);

/* Drop the partial command and every byte up to the next newline.
 *
 * The receive ring is filled from an interrupt and drained by the main loop.
 * When the ring is full the dropped bytes may include the newline separating
 * two commands, which would otherwise splice them into a single unparsable
 * line. Resynchronizing trades one command for correct framing.
 */
void keycap_line_reader_resynchronize(struct keycap_line_reader *reader);

enum keycap_line_status keycap_line_reader_push(struct keycap_line_reader *reader,
						uint8_t byte);

#endif
