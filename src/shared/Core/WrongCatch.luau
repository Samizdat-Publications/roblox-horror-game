--!strict
-- Compatibility shim: the trait mutation helper is now Core.FishMutations (renamed
-- 11/26/2026 so it no longer shares a name with the rule, entities/WrongCatch).
-- Remove once nothing outside Core requires Core.WrongCatch.
return require(script.Parent.FishMutations)
