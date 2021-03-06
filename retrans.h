/*
 * Copyright (c) 2016, Moonflow <me@zhc105.net>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

#ifndef _RETRANS_H_
#define _RETRANS_H_

#include "litedt_messages.h"
#include "litedt_fwd.h"
#include "hashqueue.h"
#include "rbuffer.h"

#define RETRANS_HASH_SIZE   10007

#pragma pack(1)
typedef struct _retrans_key {
    uint32_t flow;
    uint32_t offset;
} retrans_key_t;
#pragma pack()

typedef struct _litedt_retrans {
    int         turn;
    int64_t     retrans_time;
    uint32_t    flow;
    uint32_t    offset;
    uint32_t    length;
    uint32_t    fec_offset;
    uint8_t     fec_index;
} litedt_retrans_t;

typedef struct _retrans_mod {
    litedt_host_t*  host;
    hash_queue_t    retrans_queue;
} retrans_mod_t;

int  retrans_mod_init(retrans_mod_t *rtmod, litedt_host_t *host);
void retrans_mod_fini(retrans_mod_t *rtmod);

litedt_retrans_t* find_retrans(retrans_mod_t *rtmod, uint32_t flow, 
                               uint32_t offset);
int  create_retrans(retrans_mod_t *rtmod, uint32_t flow, uint32_t offset, 
                    uint32_t length, uint32_t fec_offset, uint8_t fec_index,
                    int64_t cur_time);
void update_retrans(retrans_mod_t *rtmod, litedt_retrans_t *retrans, 
                    int64_t cur_time);
void release_retrans(retrans_mod_t *rtmod, uint32_t flow, uint32_t offset);

void retrans_time_event(retrans_mod_t *rtmod, int64_t cur_time);
int  handle_retrans(retrans_mod_t *rtmod, litedt_retrans_t *rt, 
                    int64_t cur_time);

#endif
