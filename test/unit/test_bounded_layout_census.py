"""Census attribution at the boundaries of the bounded storage shapes."""
import importlib.util
from pathlib import Path
import unittest
path = Path(__file__).resolve().parents[2] / 'scripts/audit/storage-census/aggregate.py'
spec = importlib.util.spec_from_file_location('bounded_census', path)
census = importlib.util.module_from_spec(spec)
spec.loader.exec_module(census)

class BoundedLayoutCensusTests(unittest.TestCase):
    def setUp(self):
        self.layout = census.Layout([
            {'label':'hero','slot':'600','offset':0,'type':'hero'},
            {'label':'deities','slot':'606','offset':0,'type':'deities'},
            {'label':'foil','slot':'610','offset':0,'type':'foil'},
            {'label':'boons','slot':'614','offset':0,'type':'boons'},
            {'label':'queues','slot':'618','offset':0,'type':'queues'},
            {'label':'rounds','slot':'620','offset':0,'type':'rounds'},
        ], {
            'word': {'encoding':'inplace','numberOfBytes':'32'},
            'small': {'encoding':'inplace','numberOfBytes':'4'},
            'hero': {'encoding':'inplace','base':'quadrants','numberOfBytes':'192'},
            'quadrants': {'encoding':'inplace','base':'word','numberOfBytes':'96'},
            'deities': {'encoding':'inplace','base':'small','numberOfBytes':'128'},
            'map': {'encoding':'mapping','value':'word','numberOfBytes':'32'},
            'foil': {'encoding':'inplace','base':'map','numberOfBytes':'128'},
            'boons': {'encoding':'inplace','base':'pair','numberOfBytes':'128'},
            'pair': {'encoding':'inplace','base':'map','numberOfBytes':'64'},
            'queues': {'encoding':'inplace','base':'dynamic','numberOfBytes':'64'},
            'dynamic': {'encoding':'dynamic_array','base':'word','numberOfBytes':'32'},
            'rounds': {'encoding':'inplace','base':'round','numberOfBytes':str(512*160)},
            'round': {'encoding':'inplace','numberOfBytes':'160','members':[
                {'label':'first','slot':'0','offset':0,'type':'word'},
                {'label':'last','slot':'4','offset':0,'type':'word'},
            ]},
        })

    def test_fixed_nested_arrays_and_packed_words(self):
        for root,slot,label in [('hero',600,'hero[0][0]'),('hero',605,'hero[1][2]'),
                                ('deities',606,'deities[w0]'),('deities',609,'deities[w3]'),
                                ('rounds',620,'rounds[0].first'),('rounds',3179,'rounds[511].last')]:
            self.assertEqual(self.layout.resolve(slot,[]),(root,label,True))
        self.assertFalse(self.layout.resolve(3180,[])[2])

    def test_mapping_leaves_inside_fixed_arrays(self):
        for slot,label in [(610,'foil[0][]'),(613,'foil[3][]'),(614,'boons[0][0][]'),(617,'boons[1][1][]')]:
            self.assertEqual(self.layout.resolve(slot,['M0']),(label.split('[')[0],label,True))
        self.assertEqual(self.layout.indirect_roots(), {'mapping':set(range(610,618)),'dynamic_array':{618,619}})

    def test_dynamic_payloads_inside_fixed_array(self):
        for slot in [618,619]:
            self.assertEqual(self.layout.resolve(slot,['A123']),('queues',f'queues[{slot-618}][]',True))

    def test_second_chance_finds_nested_and_direct_heads(self):
        try:
            import Crypto
        except ImportError:
            self.skipTest('pycryptodome unavailable')
        key=7;root=617
        hashed=census._keccak(key.to_bytes(32,'big')+root.to_bytes(32,'big'))
        self.assertEqual(census.resolve_unattributed(self.layout,hex(hashed),max_key=16),(root,key,0,'M'))
        for root in [618,619]:
            payload=census._keccak(root.to_bytes(32,'big'))+23
            self.assertEqual(census.resolve_unattributed(self.layout,hex(payload),max_key=16),(root,0,23,'D'))
