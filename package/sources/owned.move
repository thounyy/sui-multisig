/// This module allows multisig members to access objects owned by the multisig in a secure way.
/// The objects can be taken only via an Withdraw action.
/// This action can't be proposed directly since it wouldn't make sense to withdraw an object without using it.
/// Objects can be borrowed by adding both a Withdraw and a Return action to the proposal.
/// This is automatically handled by the borrow functions.
/// Caution: borrowed Coins can be emptied, only withdraw the amount you need (merge and split coins before if necessary)

module kraken::owned {    
    use sui::transfer::Receiving;
    use kraken::multisig::{Multisig, Executable, Proposal};

    // === Errors ===

    const EWrongObject: u64 = 0;
    const EReturnAllObjectsBefore: u64 = 1;
    const ERetrieveAllObjectsBefore: u64 = 2;

    // === Structs ===

    // [ACTION] guard access to multisig owned objects which can only be received via this action
    public struct Withdraw has store {
        // the owned objects we want to access
        objects: vector<ID>,
    }

    // [ACTION] enforces accessed objects to be sent back to the multisig, depends on Withdraw
    public struct Return has store {
        // list of objects to put back into the multisig
        to_return: vector<ID>,
    }

    // === [ACTION] Public functions ===

    public fun new_withdraw(proposal: &mut Proposal, objects: vector<ID>) {
        proposal.add_action(Withdraw { objects });
    }

    public fun withdraw<T: key + store, W: copy + drop>(
        executable: &mut Executable,
        multisig: &mut Multisig, 
        receiving: Receiving<T>,
        witness: W,
        idx: u64,
    ): T {
        multisig.assert_executed(executable);
        let withdraw_mut: &mut Withdraw = executable.action_mut(witness, idx);
        let (_, index) = withdraw_mut.objects.index_of(&transfer::receiving_object_id(&receiving));
        let id = withdraw_mut.objects.remove(index);

        let received = transfer::public_receive(multisig.uid_mut(), receiving);
        let received_id = object::id(&received);
        assert!(received_id == id, EWrongObject);

        received
    }

    public fun destroy_withdraw<W: drop>(executable: &mut Executable, witness: W) {
        let Withdraw { objects } = executable.remove_action(witness);
        assert!(objects.is_empty(), ERetrieveAllObjectsBefore);
    }

    public fun new_borrow(proposal: &mut Proposal, objects: vector<ID>) {
        new_withdraw(proposal, objects);
        proposal.add_action(Return { to_return: objects });
    }

    public fun borrow<T: key + store, W: copy + drop>(
        executable: &mut Executable,
        multisig: &mut Multisig, 
        receiving: Receiving<T>,
        witness: W,
        idx: u64,
    ): T {
        withdraw(executable, multisig, receiving, witness, idx)
    }
    
    public fun put_back<T: key + store, W: copy + drop>(
        executable: &mut Executable,
        multisig: &Multisig, 
        returned: T, 
        witness: W,
        idx: u64,
    ) {
        multisig.assert_executed(executable);
        let borrow_mut: &mut Return = executable.action_mut(witness, idx);
        let (exists_, index) = borrow_mut.to_return.index_of(&object::id(&returned));
        assert!(exists_, EWrongObject);

        borrow_mut.to_return.remove(index);
        transfer::public_transfer(returned, multisig.addr());
    }

    public fun destroy_borrow<W: copy + drop>(executable: &mut Executable, witness: W) {
        destroy_withdraw(executable, witness);
        let Return { to_return } = executable.remove_action(witness);
        assert!(to_return.is_empty(), EReturnAllObjectsBefore);
    }
}
