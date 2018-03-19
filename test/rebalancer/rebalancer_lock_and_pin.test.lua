test_run = require('test_run').new()

REPLICASET_1 = { 'box_1_a', 'box_1_b' }
REPLICASET_2 = { 'box_2_a', 'box_2_b' }
REPLICASET_3 = { 'box_3_a', 'box_3_b' }

test_run:create_cluster(REPLICASET_1, 'rebalancer')
test_run:create_cluster(REPLICASET_2, 'rebalancer')
util = require('util')
util.wait_master(test_run, REPLICASET_1, 'box_1_a')
util.wait_master(test_run, REPLICASET_2, 'box_2_a')

--
-- A replicaset can be locked. Locked replicaset can neither
-- receive new buckets nor send own ones during rebalancing.
--

test_run:switch('box_2_a')
vshard.storage.bucket_force_create(1501, 1500)

test_run:switch('box_1_a')
vshard.storage.bucket_force_create(1, 1500)

wait_rebalancer_state('The cluster is balanced ok', test_run)

--
-- Check that a weight = 0 will not do anything with a locked
-- replicaset. Moreover, this cluster is considered to be balanced
-- ok.
--
test_run:switch('box_2_a')
rs1_cfg = cfg.sharding[names.rs_uuid[1]]
rs1_cfg.lock = true
rs1_cfg.weight = 0
vshard.storage.cfg(cfg, names.replica_uuid.box_2_a)

test_run:switch('box_1_a')
rs1_cfg = cfg.sharding[names.rs_uuid[1]]
rs1_cfg.lock = true
rs1_cfg.weight = 0
vshard.storage.cfg(cfg, names.replica_uuid.box_1_a)

wait_rebalancer_state('The cluster is balanced ok', test_run)
vshard.storage.is_locked()
info = vshard.storage.info().bucket
info.active
info.lock

--
-- Check that a locked replicaset not only blocks bucket sending,
-- but blocks receiving as well.
--
test_run:switch('box_2_a')
rs1_cfg.weight = 2
vshard.storage.cfg(cfg, names.replica_uuid.box_2_a)

test_run:switch('box_1_a')
rs1_cfg.weight = 2
vshard.storage.cfg(cfg, names.replica_uuid.box_1_a)

wait_rebalancer_state('The cluster is balanced ok', test_run)
info = vshard.storage.info().bucket
info.active
info.lock

--
-- Vshard ensures that if a replicaset is locked, then it will not
-- allow to change its bucket set even if a rebalancer does not
-- know about a lock yet. For example, a locked replicaset could
-- be reconfigured a bit earlier.
--
test_run:switch('box_2_a')
rs1_cfg.lock = false
rs2_cfg = cfg.sharding[names.rs_uuid[2]]
rs2_cfg.lock = true
vshard.storage.cfg(cfg, names.replica_uuid.box_2_a)

test_run:switch('box_1_a')
rs1_cfg.lock = false
vshard.storage.cfg(cfg, names.replica_uuid.box_1_a)

wait_rebalancer_state('Replicaset is locked', test_run)

rs2_cfg = cfg.sharding[names.rs_uuid[2]]
rs2_cfg.lock = true
vshard.storage.cfg(cfg, names.replica_uuid.box_1_a)

wait_rebalancer_state('The cluster is balanced ok', test_run)

--
-- Check that when a new replicaset is added, buckets are spreaded
-- on non-locked replicasets as if locked replicasets and buckets
-- do not exist.
--

test_run:switch('default')
test_run:create_cluster(REPLICASET_3, 'rebalancer')
util.wait_master(test_run, REPLICASET_3, 'box_3_a')

test_run:switch('box_2_a')
rs1_cfg.lock = true
rs1_cfg.weight = 1
-- Return default configuration.
rs2_cfg.lock = false
rs2_cfg.weight = 0.5
add_replicaset()
vshard.storage.cfg(cfg, names.replica_uuid.box_2_a)

test_run:switch('box_3_a')
rs1_cfg = cfg.sharding[names.rs_uuid[1]]
rs1_cfg.lock = true
rs1_cfg.weight = 1
rs2_cfg = cfg.sharding[names.rs_uuid[2]]
rs2_cfg.weight = 0.5
vshard.storage.cfg(cfg, names.replica_uuid.box_3_a)

test_run:switch('box_1_a')
rs1_cfg.lock = true
rs1_cfg.weight = 1
rs2_cfg.lock = false
rs2_cfg.weight = 0.5
add_replicaset()
vshard.storage.cfg(cfg, names.replica_uuid.box_1_a)

wait_rebalancer_state('The cluster is balanced ok', test_run)
info = vshard.storage.info().bucket
info.active
info.lock

test_run:switch('box_2_a')
vshard.storage.info().bucket.active

test_run:switch('box_3_a')
vshard.storage.info().bucket.active

test_run:cmd("switch default")
test_run:drop_cluster(REPLICASET_3)
test_run:drop_cluster(REPLICASET_2)
test_run:drop_cluster(REPLICASET_1)
