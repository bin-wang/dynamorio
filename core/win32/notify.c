/* **********************************************************
 * Copyright (c) 2010-2026 Google, Inc.  All rights reserved.
 * Copyright (c) 2017 ARM Limited. All rights reserved.
 * Copyright (c) 2000-2010 VMware, Inc.  All rights reserved.
 * **********************************************************/

/*
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * * Redistributions of source code must retain the above copyright notice,
 *   this list of conditions and the following disclaimer.
 *
 * * Redistributions in binary form must reproduce the above copyright notice,
 *   this list of conditions and the following disclaimer in the documentation
 *   and/or other materials provided with the distribution.
 *
 * * Neither the name of VMware, Inc. nor the names of its contributors may be
 *   used to endorse or promote products derived from this software without
 *   specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL VMWARE, INC. OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
 * DAMAGE.
 */

/* Copyright (c) 2003-2007 Determina Corp. */
/* Copyright (c) 2001-2003 Massachusetts Institute of Technology */
/* Copyright (c) 2000-2001 Hewlett-Packard Company */

/* Windows notification destinations. */

#include "../globals.h"
#include "stdarg_wrapper.h"

static void
do_syslog(syslog_event_type_t priority, uint message_id, uint substitutions_num, ...)
{
    va_list ap;
    va_start(ap, substitutions_num);
    os_syslog(priority, message_id, substitutions_num, ap);
    va_end(ap);
}

void
os_notify_syslog(syslog_event_type_t priority, bool internal, uint message_id,
                 uint substitution_num, const char *message, va_list args)
{
    if (TESTANY(priority, dynamo_options.syslog_mask)) {
        if (internal) {
            if (TESTANY(priority, INTERNAL_OPTION(syslog_internal_mask))) {
                do_syslog(priority, message_id, 3, get_application_name(),
                          get_application_pid(), message);
            }
        } else {
            os_syslog(priority, message_id, substitution_num, args);
        }
    }
}

void
os_notify_messagebox(char *message)
{
    /* XXX: could use os_countdown_msgbox (if ever implemented) here to
     * do a timed out messagebox, could then also replace the os_timeout in
     * vmareas.c
     */
    debugbox(message);
}

void
os_notify_set_title(void)
{
    debugbox_setup_title();
}
