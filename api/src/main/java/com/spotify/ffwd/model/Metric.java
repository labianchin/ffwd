/*
 * Copyright 2013-2017 Spotify AB. All rights reserved.
 *
 * The contents of this file are licensed under the Apache License, Version 2.0
 * (the "License"); you may not use this file except in compliance with the
 * License. You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
 * WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
 * License for the specific language governing permissions and limitations under
 * the License.
 */
package com.spotify.ffwd.model;

import java.util.Date;
import java.util.Map;
import java.util.Set;
import lombok.Data;
import lombok.EqualsAndHashCode;

/**
 * TODO: rename to 'Point' to follow along with internal guidelines.
 */
@Data
@EqualsAndHashCode(of = {"key", "riemannTags", "tags"})
public class Metric {
    private final String key;
    private final double value;
    private final Date time;
    private final Set<String> riemannTags;
    private final Map<String, String> tags;
    private final Map<String, String> resource;
    private final String proc;

    /**
     * Convert into a batch point, lose information that is not relevant for batches.
     *
     * @return a batch point
     */
    public Batch.Point toBatchPoint() {
        return new Batch.Point(key, tags, resource, value, time.getTime());
    }
}
