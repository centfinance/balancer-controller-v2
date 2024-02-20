interface IProxyInvest {
    enum JoinKind {
        EXACT_TOKENS_IN_FOR_BPT_OUT,
        TOKEN_IN_FOR_EXACT_BPT_OUT,
        ALL_TOKENS_IN_FOR_EXACT_BPT_OUT
    }

    enum ExitKind {
        EXACT_BPT_IN_FOR_ONE_TOKEN_OUT,
        EXACT_BPT_IN_FOR_ALL_TOKENS_OUT,
        BPT_IN_FOR_EXACT_TOKENS_OUT
    }

    function joinPool(
        address recipient,
        address referrer,
        address controller,
        address pool,
        IVault.JoinPoolRequest calldata request
    )
        external
        returns (
            uint256 amountToRecipient,
            uint256 amountToReferrer,
            uint256 amountToManager,
            uint256[] memory amountsIn
        );

    function exitPool(
        address sender,
        address recipient,
        address pool,
        IVault.ExitPoolRequest calldata request
    ) external returns (uint256 amountToSender, uint256[] memory amountsOut);
}
