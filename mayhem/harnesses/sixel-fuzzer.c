/*
 * Fuzz the SIXEL parser and its image placement path.
 *
 * fuzz/sixel-fuzzer.c calls sixel_free/sixel_size_in_cells, which are static in current
 * image-sixel.c, so it no longer compiles. This harness keeps the same boundary (a payload that
 * starts with 'q', as handed over by the DCS handler) and goes through the public sixel_write(),
 * which converts, places the image on a screen and frees it.
 */

#include <sys/types.h>

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "tmux.h"

#define SIXEL_FUZZER_MAXLEN 1024

extern char **environ;

int
LLVMFuzzerTestOneInput(const u_char *data, size_t size)
{
	struct sixel_image	*image;
	struct screen		 s;
	struct screen_write_ctx	 ctx;
	char			*payload;

	if (size < 2 || size > SIXEL_FUZZER_MAXLEN || data[0] != 'q')
		return (0);

	payload = malloc(size + 1);
	if (payload == NULL)
		return (0);
	memcpy(payload, data, size);
	payload[size] = '\0';

	image = sixel_parse(payload, size, 0, 8, 16);
	free(payload);
	if (image == NULL)
		return (0);

	screen_init(&s, 80, 24, 0);
	screen_write_start(&ctx, &s);
	sixel_write(&ctx, image, 8);
	screen_write_stop(&ctx);
	screen_free(&s);

	return (0);
}

int
LLVMFuzzerInitialize(__unused int *argc, __unused char ***argv)
{
	const struct options_table_entry	*oe;

	global_environ = environ_create();
	global_options = options_create(NULL);
	global_s_options = options_create(NULL);
	global_w_options = options_create(NULL);
	for (oe = options_table; oe->name != NULL; oe++) {
		if (oe->scope & OPTIONS_TABLE_SERVER)
			options_default(global_options, oe);
		if (oe->scope & OPTIONS_TABLE_SESSION)
			options_default(global_s_options, oe);
		if (oe->scope & OPTIONS_TABLE_WINDOW)
			options_default(global_w_options, oe);
	}
	return (0);
}
