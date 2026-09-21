import { DEFAULT_KANBAN_FILTERS } from './constants';

const emptyStageItemsState = () => ({
  ids: [],
  page: 1,
  count: 0,
  hasMore: true,
  isFetching: false,
  // Set when the last fetch/fetch-more for this stage failed (task 21) - distinct from a
  // legitimately empty column (ids: [], count: 0, hasError: false), and used to stop the
  // IntersectionObserver from retrying a broken column in a loop (KanbanColumn.vue only renders
  // it when hasError is false).
  hasError: false,
  // Ids counted in `count` without being loaded into `ids` - a realtime push for a card sitting
  // on a page this column hasn't fetched (task 18). Tracked so the same id can't move `count`
  // twice for the same matched/unmatched state.
  unloadedCountedIds: [],
});

// itemIdsByContact/itemIdsByConversation (task 10) let getItemsForContact/getItemsForConversation
// map ids instead of scanning every item ever loaded into $state.items. Kept as plain
// { [key]: itemId[] } objects, same shape/style as the rest of the module's indices.
function addToIndex(index, key, itemId) {
  if (key == null) return index;
  const ids = index[key] || [];
  if (ids.includes(itemId)) return index;
  return { ...index, [key]: [...ids, itemId] };
}

function removeFromIndex(index, key, itemId) {
  if (key == null || !index[key]) return index;
  const ids = index[key].filter(id => id !== itemId);
  if (ids.length === index[key].length) return index;
  if (ids.length === 0) {
    const { [key]: _removed, ...rest } = index;
    return rest;
  }
  return { ...index, [key]: ids };
}

function isIndexed(index, key, itemId) {
  return key != null && (index[key] || []).includes(itemId);
}

function reindex($state, indexName, oldKey, newKey, itemId, addNew) {
  const wasIndexed = isIndexed($state[indexName], oldKey, itemId);
  if (oldKey !== newKey) {
    $state[indexName] = removeFromIndex($state[indexName], oldKey, itemId);
  }
  if (addNew || (wasIndexed && oldKey !== newKey)) {
    $state[indexName] = addToIndex($state[indexName], newKey, itemId);
  }
}

// Gives back the +1 an unloaded card is still costing every stage that isn't `exceptStageId`
// (task 27), for when that card is now known to live somewhere else. Two sources:
//   - stages tracking it in `unloadedCountedIds` (task 18) - dropped from that list and
//     decremented;
//   - `previousStageId`, when the realtime push says which stage the card just left: that stage's
//     `count` (from the server's meta.count) still includes it even though this client never
//     tracked it, so it's decremented too - unless the tracked path above already did.
// Returns the same object untouched when nothing needed releasing, so callers can assign it
// unconditionally.
function releaseUnloadedCount(
  stageItems,
  itemId,
  exceptStageId,
  previousStageId
) {
  let result = stageItems;
  const released = new Set();
  Object.entries(stageItems).forEach(([key, stage]) => {
    const stageId = Number(key);
    if (stageId === exceptStageId) return;
    if (!stage.unloadedCountedIds.includes(itemId)) return;
    released.add(stageId);
    result = {
      ...result,
      [key]: {
        ...stage,
        unloadedCountedIds: stage.unloadedCountedIds.filter(
          id => id !== itemId
        ),
        count: Math.max(0, stage.count - 1),
      },
    };
  });

  const previous = result[previousStageId];
  if (
    previous &&
    previousStageId !== exceptStageId &&
    !released.has(previousStageId) &&
    !previous.ids.includes(itemId)
  ) {
    result = {
      ...result,
      [previousStageId]: {
        ...previous,
        count: Math.max(0, previous.count - 1),
      },
    };
  }
  return result;
}

// Called with the item as it was in $state.items before this write (undefined for a brand new
// item) and `patch`, whatever was just passed to the mutation - a full item or a partial one
// (e.g. `{ id, label_list }` from fetchItemLabels). A key is only reindexed when `patch` actually
// carries it - a partial patch that omits `contact`/`conversation_id` must not be read as
// "cleared". `contact_id` never actually changes after a card is created, but `conversation_id`
// does (KanbanCardDetail's link/unlink conversation actions), so both go through the same
// old-value/new-value diff rather than assuming append-only.
//
// `addNew` is what separates the two origins an item can have (task 25): only SET_ITEM_DATA (the
// Opportunities panels' fetch) passes it, and only then does an id enter the index. Every other
// write - board pages, SET_ITEM, EDIT_ITEM - just keeps an id that's *already* indexed consistent
// (moved to its new bucket, or dropped), and never adds one. That's what lets
// SET_ACTIVE_PIPELINE tell "only the board ever held this" from "a panel is looking at this".
function syncItemIndices($state, previousItem, patch, { addNew = false } = {}) {
  if ('contact' in patch) {
    reindex(
      $state,
      'itemIdsByContact',
      previousItem?.contact?.id ?? null,
      patch.contact?.id ?? null,
      patch.id,
      addNew
    );
  }
  if ('conversation_id' in patch) {
    reindex(
      $state,
      'itemIdsByConversation',
      previousItem?.conversation_id ?? null,
      patch.conversation_id ?? null,
      patch.id,
      addNew
    );
  }
}

const mutations = {
  SET_KANBAN_FILTERS($state, filters) {
    $state.activeFilters = { ...$state.activeFilters, ...filters };
  },

  RESET_KANBAN_FILTERS($state) {
    $state.activeFilters = { ...DEFAULT_KANBAN_FILTERS };
  },

  SET_KANBAN_SORT($state, sort) {
    $state.activeSort = { ...$state.activeSort, ...sort };
  },

  SET_SHOW_ONLY_MINE($state, value) {
    $state.showOnlyMine = value;
  },

  SET_KANBAN_UI_FLAG($state, data) {
    $state.uiFlags = { ...$state.uiFlags, ...data };
  },

  SET_PIPELINES($state, pipelines) {
    const records = {};
    const order = [];
    pipelines.forEach(p => {
      records[p.id] = p;
      order.push(p.id);
      if (p.stages) {
        p.stages.forEach(s => {
          $state.stages[s.id] = s;
        });
        $state.stageOrder[p.id] = p.stages.map(s => s.id);
      }
    });
    $state.pipelines = records;
    $state.pipelineOrder = order;
  },

  SET_PIPELINE_ITEM($state, pipeline) {
    $state.pipelines[pipeline.id] = pipeline;
    if (!$state.pipelineOrder.includes(pipeline.id)) {
      $state.pipelineOrder = [...$state.pipelineOrder, pipeline.id];
    }
    if (pipeline.stages) {
      pipeline.stages.forEach(s => {
        $state.stages[s.id] = s;
      });
      $state.stageOrder[pipeline.id] = pipeline.stages.map(s => s.id);
    }
  },

  EDIT_PIPELINE($state, pipeline) {
    $state.pipelines[pipeline.id] = {
      ...($state.pipelines[pipeline.id] || {}),
      ...pipeline,
    };
  },

  DELETE_PIPELINE($state, pipelineId) {
    const { [pipelineId]: _removed, ...remaining } = $state.pipelines;
    $state.pipelines = remaining;
    $state.pipelineOrder = $state.pipelineOrder.filter(id => id !== pipelineId);
    if ($state.activePipelineId === pipelineId) {
      $state.activePipelineId = $state.pipelineOrder[0] || null;
    }
  },

  SET_STAGES($state, { pipelineId, stages }) {
    stages.forEach(s => {
      $state.stages[s.id] = s;
    });
    $state.stageOrder[pipelineId] = stages.map(s => s.id);
  },

  SET_STAGE_ITEM($state, { pipelineId, stage }) {
    $state.stages[stage.id] = stage;
    const order = $state.stageOrder[pipelineId] || [];
    if (!order.includes(stage.id)) {
      $state.stageOrder[pipelineId] = [...order, stage.id];
    }
  },

  EDIT_STAGE($state, stage) {
    $state.stages[stage.id] = { ...($state.stages[stage.id] || {}), ...stage };
  },

  DELETE_STAGE($state, { pipelineId, stageId }) {
    const { [stageId]: _removed, ...remaining } = $state.stages;
    $state.stages = remaining;
    $state.stageOrder[pipelineId] = (
      $state.stageOrder[pipelineId] || []
    ).filter(id => id !== stageId);
  },

  // Page 1 of a stage's items - replaces whatever was loaded for that column so far.
  SET_STAGE_ITEMS_PAGE($state, { stageId, items, count, page }) {
    items.forEach(item => {
      syncItemIndices($state, $state.items[item.id], item);
      $state.items[item.id] = item;
    });
    $state.stageItems[stageId] = {
      ids: items.map(item => item.id),
      page,
      count,
      hasMore: items.length < count,
      isFetching: false,
      hasError: false,
      // A fresh page 1 carries an authoritative count straight from the server (task 18) - any
      // realtime bookkeeping accumulated before this fetch is superseded by it, not merely
      // reconciled against page 1's ids.
      unloadedCountedIds: [],
    };
  },

  // A later page of a stage's items - appends. Guards against double-inserting an id, in case
  // the IntersectionObserver (task 06) fires more than once for the same page.
  APPEND_STAGE_ITEMS_PAGE($state, { stageId, items, count, page }) {
    items.forEach(item => {
      syncItemIndices($state, $state.items[item.id], item);
      $state.items[item.id] = item;
    });
    const existing = $state.stageItems[stageId] || emptyStageItemsState();
    const newIds = items
      .map(item => item.id)
      .filter(id => !existing.ids.includes(id));
    const ids = [...existing.ids, ...newIds];
    $state.stageItems[stageId] = {
      ids,
      page,
      count,
      hasMore: ids.length < count,
      isFetching: false,
      hasError: false,
      // These ids are now tracked via `ids` - drop them from the realtime-only bookkeeping (task
      // 18) so a later update for one of them goes through the loaded-item path instead.
      unloadedCountedIds: existing.unloadedCountedIds.filter(
        id => !ids.includes(id)
      ),
    };
  },

  SET_STAGE_FETCHING($state, { stageId, isFetching }) {
    const existing = $state.stageItems[stageId] || emptyStageItemsState();
    $state.stageItems[stageId] = { ...existing, isFetching };
  },

  // Task 21: a failed fetch/fetch-more leaves the column visually distinct from a legitimately
  // empty one, and stops the IntersectionObserver from retrying it in a loop (KanbanColumn.vue
  // only renders the observer when hasError is false).
  SET_STAGE_ERROR($state, { stageId, hasError }) {
    const existing = $state.stageItems[stageId] || emptyStageItemsState();
    $state.stageItems[stageId] = { ...existing, hasError };
  },

  // Idempotent per id (task 18): whether `itemId` is currently one of the "matches the active
  // filters but isn't loaded into `ids`" cards counted in this stage's `count`. Calling this
  // again with the same `counted` value for an id that's already in that state is a no-op -
  // that's what stops a bulk macro re-pushing pipeline_item.updated for the same unloaded card
  // from inflating the badge once per event. The same call also releases the id from any *other*
  // stage still counting it (task 27) - a push for `stageId` is the latest word on where the card
  // lives, so a count it left behind in its previous stage is stale, whether or not it matches
  // here (`counted: false`). `previousStageId`, when the push says which stage the card just left,
  // extends that to a stage that never tracked it (see releaseUnloadedCount).
  SET_UNLOADED_ITEM_COUNTED(
    $state,
    { stageId, itemId, counted, previousStageId }
  ) {
    $state.stageItems = releaseUnloadedCount(
      $state.stageItems,
      itemId,
      stageId,
      previousStageId
    );
    const existing = $state.stageItems[stageId] || emptyStageItemsState();
    const alreadyCounted = existing.unloadedCountedIds.includes(itemId);
    if (counted === alreadyCounted) return;

    $state.stageItems[stageId] = {
      ...existing,
      unloadedCountedIds: counted
        ? [...existing.unloadedCountedIds, itemId]
        : existing.unloadedCountedIds.filter(id => id !== itemId),
      count: Math.max(0, existing.count + (counted ? 1 : -1)),
    };
  },

  // Adds a freshly created item to its stage's loaded list - the creating agent should see it
  // immediately regardless of active filters - and bumps that stage's count. If the realtime
  // push for this same card already counted it as "matched but unloaded" (POST and WS racing,
  // task 18), transfer it into `ids` without counting it a second time.
  SET_ITEM($state, item) {
    syncItemIndices($state, $state.items[item.id], item);
    $state.items[item.id] = item;
    const stageId = item.pipeline_stage_id;
    const existing = $state.stageItems[stageId] || emptyStageItemsState();
    if (existing.ids.includes(item.id)) return;

    const wasUnloadedCounted = existing.unloadedCountedIds.includes(item.id);
    $state.stageItems[stageId] = {
      ...existing,
      ids: [...existing.ids, item.id],
      unloadedCountedIds: wasUnloadedCounted
        ? existing.unloadedCountedIds.filter(id => id !== item.id)
        : existing.unloadedCountedIds,
      count: wasUnloadedCounted ? existing.count : existing.count + 1,
    };
  },

  // Stores item data only — does NOT touch stageItems (used by contact/conversation lookups to
  // avoid polluting a column's loaded list/count before that column has actually been fetched)
  SET_ITEM_DATA($state, item) {
    syncItemIndices($state, $state.items[item.id], item, { addNew: true });
    $state.items[item.id] = { ...($state.items[item.id] || {}), ...item };
  },

  EDIT_ITEM($state, item) {
    syncItemIndices($state, $state.items[item.id], item);
    $state.items[item.id] = { ...($state.items[item.id] || {}), ...item };
  },

  // Removes an item entirely (deleted, or exported to another pipeline) - drops it from the
  // item dictionary, from the contact/conversation lookup indices, and from whatever stage
  // list/count had it loaded.
  DELETE_ITEM($state, { stageId, itemId }) {
    const removedItem = $state.items[itemId];
    $state.itemIdsByContact = removeFromIndex(
      $state.itemIdsByContact,
      removedItem?.contact?.id,
      itemId
    );
    $state.itemIdsByConversation = removeFromIndex(
      $state.itemIdsByConversation,
      removedItem?.conversation_id,
      itemId
    );
    const { [itemId]: _removed, ...remaining } = $state.items;
    $state.items = remaining;
    $state.stageItems = releaseUnloadedCount($state.stageItems, itemId);
    const existing = $state.stageItems[stageId];
    if (!existing) return;
    const hadItem = existing.ids.includes(itemId);
    $state.stageItems[stageId] = {
      ...existing,
      ids: existing.ids.filter(id => id !== itemId),
      count: hadItem ? Math.max(0, existing.count - 1) : existing.count,
    };
  },

  // Puts an item that no stage list holds (task 28: one only counted as unloaded, until a realtime
  // push says where it now sorts) into a stage's loaded list at `position`, and counts it there.
  INSERT_STAGE_ITEM($state, { stageId, itemId, position }) {
    const existing = $state.stageItems[stageId] || emptyStageItemsState();
    if (existing.ids.includes(itemId)) return;
    const ids = [...existing.ids];
    ids.splice(position, 0, itemId);
    $state.stageItems[stageId] = {
      ...existing,
      ids,
      count: existing.count + 1,
    };
  },

  // Removes an item from one stage's loaded list/count without touching the item dictionary -
  // used when a realtime update makes an already-loaded card stop matching the active filter
  // (it still exists, just not in this filtered column view anymore).
  REMOVE_STAGE_ITEM($state, { stageId, itemId }) {
    const existing = $state.stageItems[stageId];
    if (!existing) return;
    const hadItem = existing.ids.includes(itemId);
    $state.stageItems[stageId] = {
      ...existing,
      ids: existing.ids.filter(id => id !== itemId),
      count: hadItem ? Math.max(0, existing.count - 1) : existing.count,
    };
  },

  // Moves an item between two stages' loaded lists, keeping both counts in sync. Only touches
  // list/count bookkeeping when the item was actually part of the source stage's loaded list
  // (e.g. an item only ever loaded via SET_ITEM_DATA was never tracked in any stage's list) -
  // $state.items still gets the new pipeline_stage_id either way.
  MOVE_ITEM($state, { itemId, fromStageId, toStageId, position }) {
    const fromExisting =
      $state.stageItems[fromStageId] || emptyStageItemsState();
    const wasInFrom = fromExisting.ids.includes(itemId);

    if (wasInFrom) {
      $state.stageItems[fromStageId] = {
        ...fromExisting,
        ids: fromExisting.ids.filter(id => id !== itemId),
        count: Math.max(0, fromExisting.count - 1),
      };

      const toExisting = $state.stageItems[toStageId] || emptyStageItemsState();
      const destIds = toExisting.ids.filter(id => id !== itemId);
      destIds.splice(position, 0, itemId);
      $state.stageItems[toStageId] = {
        ...toExisting,
        ids: destIds,
        count: toExisting.count + 1,
      };
    }

    if ($state.items[itemId]) {
      $state.items[itemId] = {
        ...$state.items[itemId],
        pipeline_stage_id: toStageId,
      };
    }
  },

  // Switching pipelines drops every loaded column, so $state.items would otherwise keep
  // accumulating cards for the rest of the agent's session (task 10). The two lookup indices only
  // ever hold ids that an Opportunities panel fetched itself (SET_ITEM_DATA - see syncItemIndices,
  // task 25); the board's own pages never enter them. So "not in an index" means "only a column of
  // the pipeline just left ever held this", and that's what gets dropped. What a panel is
  // showing stays, since its ids are in an index regardless of which pipeline the board has
  // active. The indices themselves need no pruning here: nothing they list is ever dropped from
  // $state.items by this, and DELETE_ITEM already removes an id from both.
  SET_ACTIVE_PIPELINE($state, pipelineId) {
    $state.activePipelineId = pipelineId;
    $state.stageItems = {};

    const keepIds = new Set(
      [
        ...Object.values($state.itemIdsByContact),
        ...Object.values($state.itemIdsByConversation),
      ].flat()
    );
    $state.items = Object.fromEntries(
      Object.entries($state.items).filter(([id]) => keepIds.has(Number(id)))
    );
  },

  REORDER_STAGES($state, { pipelineId, orderedIds }) {
    $state.stageOrder[pipelineId] = orderedIds;
  },

  REORDER_ITEMS($state, { stageId, orderedIds }) {
    const existing = $state.stageItems[stageId] || emptyStageItemsState();
    $state.stageItems[stageId] = { ...existing, ids: orderedIds };
  },
};

export default mutations;
