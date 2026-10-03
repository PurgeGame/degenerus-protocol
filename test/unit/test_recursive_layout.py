import copy,importlib.util,json,pathlib,tempfile,unittest
spec=importlib.util.spec_from_file_location('recursive_layout',pathlib.Path(__file__).resolve().parents[2]/'scripts/layout/check_recursive_layout.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class RecursiveLayoutTests(unittest.TestCase):
 def fixture(self):
  return {'storage':[{'label':'rounds','slot':'7','offset':0,'type':'mapping'}],'types':{'mapping':{'label':'mapping(uint256 => struct Round)','encoding':'mapping','numberOfBytes':'32','key':'u256','value':'struct42'},'u256':{'label':'uint256','encoding':'inplace','numberOfBytes':'32'},'u128':{'label':'uint128','encoding':'inplace','numberOfBytes':'16'},'struct42':{'label':'struct Round','encoding':'inplace','numberOfBytes':'32','members':[{'label':'cursor','slot':'0','offset':0,'type':'u128'},{'label':'paid','slot':'0','offset':16,'type':'u128'}]}}}
 def test_packed_members_swap_cannot_hide_in_same_outer_type(self):
  before=self.fixture();after=copy.deepcopy(before);m=after['types']['struct42']['members'];m[0]['offset'],m[1]['offset']=16,0
  self.assertNotEqual(module.normalize(before),module.normalize(after))
 def test_nested_member_type_change_detected(self):
  before=self.fixture();after=copy.deepcopy(before);after['types']['struct42']['members'][1]['type']='u256'
  self.assertNotEqual(module.normalize(before),module.normalize(after))
 def test_ast_identifier_change_is_ignored(self):
  before=self.fixture();after=copy.deepcopy(before);after['types']['struct900']=after['types'].pop('struct42');after['types']['mapping']['value']='struct900'
  self.assertEqual(module.normalize(before),module.normalize(after))
 def test_recursive_mapping_terminates_and_preserves_member(self):
  before=self.fixture();before['types']['struct42']['members'].append({'label':'next','slot':'1','offset':0,'type':'mapping'})
  self.assertIn('recursive',str(module.normalize(before)))
 def test_empty_layout_is_retained_and_duplicate_artifact_rejected(self):
  with tempfile.TemporaryDirectory() as directory:
   out=pathlib.Path(directory);(out/'A').mkdir();(out/'B').mkdir()
   artifact={'storageLayout':{'storage':[],'types':{}}}
   (out/'A/MissingModule.json').write_text(json.dumps(artifact))
   self.assertEqual(module.read(out),{'MissingModule':[]})
   (out/'B/MissingModule.json').write_text(json.dumps(artifact))
   with self.assertRaisesRegex(ValueError,'duplicate'):
    module.read(out)
 def test_expected_modules_come_from_deployment_registry(self):
  self.assertEqual(len(module.expected_modules()),16)
  self.assertIn('DegenerusGameRngModule',module.expected_modules())
