#!/usr/bin/env python3
"""Build table/engine/lifecycle grouping counterfactuals under the same EIP pins."""
import argparse,copy,importlib.util,json,re
from pathlib import Path
spec=importlib.util.spec_from_file_location('grouping',Path(__file__).with_name('build-grouping-variants.py'));g=importlib.util.module_from_spec(spec);spec.loader.exec_module(g)
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--baseline',type=Path,required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args();a.out.mkdir(parents=True,exist_ok=True)
base=json.loads((a.baseline/'profile-input.json').read_text());pins=dict(re.findall(r'address internal constant (\w+)\s*=\s*address\((0x[0-9a-fA-F]+)\)',base['sources']['contracts/ContractAddresses.sol']['content']))
file='contracts/profiles/eip170/Eip170Craps.sol'
head='''// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {CrapsBattleCore} from "../../modules/CrapsBattleCore.sol";
import {CrapsLifecycleRouter} from "../../modules/CrapsLifecycleRouter.sol";
import {JackpotBattle} from "../../JackpotBattle.sol";
import {CrapsEngine} from "../../CrapsEngine.sol";
import {Craps} from "../../Craps.sol";
import {ContractAddresses} from "../../ContractAddresses.sol";
'''
engine='''function _crapsSettleBattle(uint256 betId, uint256 header, uint256 chipFlip, uint256 bankroll, uint256 goal, uint48 bound, uint256 field, uint256 word) internal pure override returns (Craps.SlipResult memory) {
 return settleBattle(betId, header, chipFlip, bankroll, goal, bound, field, word);
}'''
variants={
 'engine-combined':head+'contract Eip170Craps is CrapsBattleCore, CrapsLifecycleRouter, CrapsEngine {'+engine+'}',
 'lifecycle-combined':head+'contract Eip170Craps is JackpotBattle, CrapsBattleCore {}',
 'all-combined':Path('contracts/profiles/glamsterdam/GlamsterdamCraps.sol').read_text().replace('contract GlamsterdamCraps','contract Eip170Craps'),
 'engine-delegate':head+'''contract Eip170Craps is CrapsBattleCore, CrapsLifecycleRouter {
 function _crapsSettleBattle(uint256 betId, uint256 header, uint256 chipFlip, uint256 bankroll, uint256 goal, uint48 bound, uint256 field, uint256 word) internal view override returns (Craps.SlipResult memory) {
  (bool ok, bytes memory result) = address(this).staticcall(abi.encodeWithSelector(this.delegateEngine.selector, abi.encodeWithSelector(CrapsEngine.settleBattle.selector, betId, header, chipFlip, bankroll, goal, bound, field, word)));
  if (!ok) assembly ("memory-safe") { revert(add(result,32),mload(result)) }
  return abi.decode(result,(Craps.SlipResult));
 }
 function delegateEngine(bytes calldata input) external {
  address target = ContractAddresses.CRAPS_ENGINE;
  assembly ("memory-safe") {
   let ptr := mload(0x40)
   calldatacopy(ptr,input.offset,input.length)
   let ok := delegatecall(gas(),target,ptr,input.length,0,0)
   returndatacopy(ptr,0,returndatasize())
   if iszero(ok) { revert(ptr,returndatasize()) }
   return(ptr,returndatasize())
  }
 }
}''',
 'lifecycle-external':base['sources'][file]['content'],
}
results=[]
for name,source in variants.items():
 request=copy.deepcopy(base);request['sources'][file]['content']=source
 if name=='lifecycle-external':
  k='contracts/modules/CrapsLifecycleRouter.sol';request['sources'][k]['content']=request['sources'][k]['content'].replace('delegatecall(gas(), target, data, calldatasize(), 0, 0)','call(gas(), target, 0, data, calldatasize(), 0, 0)')
 request['settings']['outputSelection']={'contracts/CrapsBattle.sol':{'CrapsBattle':['abi','evm.deployedBytecode.object','evm.deployedBytecode.immutableReferences']}}
 result=g.compile_input(request,a.out,name);code=result['contracts']['contracts/CrapsBattle.sol']['CrapsBattle']['evm']['deployedBytecode'];assert not code.get('immutableReferences')
 size=len(code['object'])//2
 (a.out/f'{name}-runtimes.json').write_text(json.dumps({pins['CRAPS'].lower():'0x'+code['object']}))
 results.append(dict(variant=name,runtimeBytes=size,fitsEip170=size<=24576));print(results[-1],flush=True)
(a.out/'sizes.json').write_text(json.dumps(results,indent=2))
