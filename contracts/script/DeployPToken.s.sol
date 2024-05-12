import {BatchScript} from "forge-safe/src/BatchScript.sol";
import {LibString} from "solady/utils/LibString.sol";

import {PointTokenVault} from "../PointTokenVault.sol";

import {console} from "forge-std/Test.sol";

contract DeployPToken is BatchScript {

    address constant POINT_TOKEN_VAULT_ADDRESS = 0x1EeEBa76f211C4Dce994b9c5A74BDF25DB649Fa1;

    string constant PTOKEN_NAME = "Rumpel kPoint: Ethena S2";
    string constant PTOKEN_SYMBOL = "pkSATS";

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        
        PointTokenVault pointTokenVault = PointTokenVault(payable(POINT_TOKEN_VAULT_ADDRESS));

        bytes32 pointsId = LibString.packTwo(PTOKEN_NAME, PTOKEN_SYMBOL);
        
        vm.startBroadcast(deployerPrivateKey);
        pointTokenVault.deployPToken(pointsId);
        vm.stopBroadcast();

        console.log("P TOKEN ADDRESS:");
        console.log(address(pointTokenVault.pTokens(pointsId)));
    }
}