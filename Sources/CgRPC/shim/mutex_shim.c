/*
 * Copyright 2016, gRPC Authors All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
#include "internal.h"
#include "cgrpc.h"

cgrpc_mutex *cgrpc_mutex_create() {
  cgrpc_mutex *mu = (cgrpc_mutex *) malloc(sizeof(cgrpc_mutex));
  gpr_mu_init(mu);
  return mu;
}

void cgrpc_mutex_destroy(cgrpc_mutex *mu) {
  gpr_mu_destroy(mu);
  free(mu);
}

void cgrpc_mutex_lock(cgrpc_mutex *mu) {
  gpr_mu_lock(mu);
}

void cgrpc_mutex_unlock(cgrpc_mutex *mu) {
  gpr_mu_unlock(mu);
}
