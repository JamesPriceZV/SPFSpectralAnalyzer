import struct

class SpcParser:
    def __init__(self, filename):
        self.filename = filename
        self.params = None
        self.nameXData = None
        self.nameYData = None
        self.name00 = None
        self.name05 = None
        self.name08 = None
        self.name12 = None
        self.setToDataPath = None
        self.namelist = None
        self.dataSetGroupDir = None
        self.groupDirContents = None
        self.dataSets = None
        self.consts = {
            'HEADERSIZE': 512,
            'SUBSECT_SIZE': 128,
            'SECT_SIZE_IND': 0,
            'MINI_SECT_SIZE_IND': 1,
            'NUM_SAT_IND': 2,
            'SID_ROOT_IND': 3,
            'MINISTREAM_CUTOFF_IND': 4,
            'SID_SSAT_IND': 5,
            'NUM_SSAT_IND': 7,
            'SID_SAT_IND': 7,
            'SID_MINI_IND': 8,
            'SUB_SECTOR_SIZE': 128,
            'MSAT_OFFSET': 76
        }

    def extract_data(self):
        with open(self.filename, 'rb') as f:
            self.params = self.get_params(f)

            self.nameXData = b'\x58\x00\x20\x00\x44\x00\x61\x00\x74\x00\x61\x00\x2e\x00\x31\x00\x00\x00'.decode('utf-8')
            self.nameYData = b'\x59\x00\x20\x00\x44\x00\x61\x00\x74\x00\x61\x00\x2e\x00\x31\x00\x00\x00'.decode('utf-8')
            self.name00 = b'\x52\x00\x6f\x00\x6f\x00\x74\x00\x20\x00\x45\x00\x6e\x00\x74\x00\x72\x00\x79\x00\x00\x00'.decode('utf-8')
            self.name05 = b'\x44\x00\x61\x00\x74\x00\x61\x00\x53\x00\x74\x00\x6f\x00\x72\x00\x61\x00\x67\x00\x65\x00\x31\x00\x00\x00'.decode('utf-8')
            self.name08 = b'\x44\x00\x61\x00\x74\x00\x61\x00\x53\x00\x65\x00\x74\x00\x47\x00\x72\x00\x6f\x00\x75\x00\x70\x00\x00\x00'.decode('utf-8')
            self.name12 = b'\x44\x00\x61\x00\x74\x00\x61\x00\x53\x00\x65\x00\x74\x00\x47\x00\x72\x00\x6f\x00\x75\x00\x70\x00\x48\x00\x65\x00\x61\x00\x64\x00\x65\x00\x72\x00\x49\x00\x6e\x00\x66\x00\x6f\x00\x00\x00'.decode('utf-8')

            self.setToDataPath = [
                b'\x44\x00\x61\x00\x74\x00\x61\x00\x53\x00\x70\x00\x65\x00\x63\x00\x74\x00\x72\x00\x75\x00\x6d\x00\x53\x00\x74\x00\x6f\x00\x72\x00\x61\x00\x67\x00\x65\x00\x00\x00'.decode('utf-8'),
                b'\x44\x00\x61\x00\x74\x00\x61\x00\x00\x00'.decode('utf-8')
            ]

            self.namelist = [self.name00, self.name05, self.name08]
            self.dataSetGroupDir = self.dir_from_path(0, self.namelist, self.params, f)
            self.groupDirContents = self.traverse_dir_sibs(self.get_dir_lrc(self.dataSetGroupDir, self.params, f)[2], self.params, f)
            self.dataSets = [d for d in self.groupDirContents if self.get_dir_name(d, self.params, f) != self.name12]

    def get_data(self):
        x_data = []
        y_data = []

        with open(self.filename, 'rb') as f:
            for ds in self.dataSets:
                name = self.get_dir_name(ds, self.params, f)
                data_dir = self.dir_from_path(ds, [name] + self.setToDataPath, self.params, f)

                for child in self.traverse_dir_sibs(self.get_dir_lrc(data_dir, self.params, f)[2], self.params, f):
                    child_name = self.get_dir_name(child, self.params, f)
                    if child_name == self.nameXData:
                        x_data = self.bytes_to_arr(self.get_dir_stream(child, self.params, f), 'd')
                    elif child_name == self.nameYData:
                        y_data = self.bytes_to_arr(self.get_dir_stream(child, self.params, f), 'd')

        return x_data, y_data

    def get_params(self, f):
        # Sector size (powers of two)
        f.seek(30, 0)
        sect_size = 1 << struct.unpack('h', f.read(2))[0]

        # Mini sector (powers of two)
        mini_sect_size = 1 << struct.unpack('h', f.read(2))[0]

        # Number of SAT sectors
        f.seek(44, 0)
        num_sat = struct.unpack('i', f.read(4))[0]

        # Root directory
        sid_root = struct.unpack('i', f.read(4))[0]

        # Ministream size cutoff
        f.seek(56, 0)
        ministream_cutoff = struct.unpack('i', f.read(4))[0]

        # SSAT index
        sid_ssat = struct.unpack('i', f.read(4))[0]

        # Num SSAT sectors
        num_ssat = struct.unpack('i', f.read(4))[0]

        # SAT index
        f.seek(76, 0)
        sid_sat = struct.unpack('i', f.read(4))[0]

        # Ministream index
        f.seek(self.consts['HEADERSIZE'] + sect_size * sid_root + 116)
        sid_mini = struct.unpack('i', f.read(4))[0]

        return (sect_size, mini_sect_size, num_sat, sid_root, ministream_cutoff, sid_ssat, num_ssat, sid_sat, sid_mini)

    def dir_from_path(self, root, namelist, params, f):
        offset = self.dir_ind_to_offset(root, params, f)
        node = root
        for name in namelist[:-1]:
            node = self.find_in_tree(name, node, params, f)
            if node == -1:
                print("Path led to empty node :(")
                break
            node = self.get_dir_lrc(node, params, f)[2]

        return self.find_in_tree(namelist[-1], node, params, f)
    
    def str_comp(self, str1, str2):
        if len(str1) != len(str2):
            return len(str1) > len(str2)
        return str1 > str2
    
    def find_in_tree(self, name, ind, params, f):
        nodeName = self.get_dir_name(ind, params, f)
        while nodeName != name:
            L, R, C = self.get_dir_lrc(ind, params, f)

            if self.str_comp(name, nodeName):
                ind = R
            else:
                ind = L
            if ind == -1:
                break
            nodeName = self.get_dir_name(ind, params, f)
        return ind

    def traverse_dir_sibs(self, ind, params, f):
        nodes = []
        queue = [ind]
        while queue:
            node = queue.pop()
            nodes.append(node)
            L, R, C = self.get_dir_lrc(node, params, f)
            if L > -1:
                queue.append(L)
            if R > -1:
                queue.append(R)
        return nodes

    def get_dir_name(self, ind, params, f):
        offset = self.dir_ind_to_offset(ind, params, f)
        f.seek(offset + 64)
        length = struct.unpack('h', f.read(2))[0]
        f.seek(offset)
        return f.read(length).decode('utf-8')

    def get_dir_stream(self, ind, params, f):
        offset = self.dir_ind_to_offset(ind, params, f) + 116
        f.seek(offset)
        stream_ind = struct.unpack('i', f.read(4))[0]
        stream_size = struct.unpack('i', f.read(4))[0]
        return self.get_stream_contents(stream_ind, stream_size, params, f)

    def bytes_to_arr(self, b, fmt):
        n = len(b) // struct.calcsize(fmt)
        return struct.unpack(str(n) + fmt, b)

    def get_dir_lrc(self, ind, params, f):
        offset = self.dir_ind_to_offset(ind, params, f)
        f.seek(offset + 68)
        left_ind = struct.unpack('i', f.read(4))[0]
        right_ind = struct.unpack('i', f.read(4))[0]
        child_ind = struct.unpack('i', f.read(4))[0]
        return (left_ind, right_ind, child_ind)

    def dir_ind_to_offset(self, ind, params, f):
        offset = ind * self.consts['SUB_SECTOR_SIZE']
        sid = params[self.consts['SID_ROOT_IND']]
        sect_size = params[self.consts['SECT_SIZE_IND']]
        sat_offset = params[self.consts['SID_SAT_IND']] * sect_size + self.consts['HEADERSIZE']
        
        while offset >= sect_size:
            offset -= sect_size
            f.seek(sat_offset + 4 * sid)
            sid = struct.unpack('i', f.read(4))[0]
            if sid == -1:
                print("Error: reached end of the sector chain before desired offset")
                break
        
        return sid * sect_size + self.consts['HEADERSIZE'] + offset

    def stream_ind_to_offset(self, ind, params, f):
        sect_size = params[self.consts['SECT_SIZE_IND']]
        sat_offset = params[self.consts['SID_SAT_IND']] * sect_size + self.consts['HEADERSIZE']
        sid = params[self.consts['SID_MINI_IND']]
        sid_ssat = params[self.consts['SID_SSAT_IND']]
        offset = ind * params[self.consts['MINI_SECT_SIZE_IND']]

        # Follow SAT chain for ministream until desired offset is reached
        while offset >= sect_size:
            offset -= sect_size
            f.seek(sat_offset + sid * 4)
            sid = struct.unpack('i', f.read(4))[0]
            if sid == -1:
                print("Error: reached end of the sector chain before desired offset")
                break
        
        return sid * sect_size + self.consts['HEADERSIZE'] + offset

    def remove_null(self, s1):
        s2 = ""
        for char in s1:
            if char != '\x00':
                s2 += char
        return s2

    def get_next_sect(self, sid, params, f):
        sect_size = params[self.consts['SECT_SIZE_IND']]
        offset = 4 * sid
        sid_sat = params[self.consts['SID_SAT_IND']]

        # Not taking into account possibility of multiple MSATS, it probably won't happen and
        # it's late and I don't give a shit
        msat_ind = 0
        while offset >= sect_size:
            offset -= sect_size
            msat_ind += 1
            
        f.seek(self.consts['MSAT_OFFSET'] + 4 * msat_ind)
        sid_sat = struct.unpack('i', f.read(4))[0]
            
        f.seek(sid_sat * sect_size + self.consts['HEADERSIZE'] + offset)
        return struct.unpack('i', f.read(4))[0]

    def get_next_mini_sect(self, ind, params, f):
        sect_size = params[self.consts['SECT_SIZE_IND']]
        sid = params[self.consts['SID_SSAT_IND']]
        ssat_offset = sid * sect_size + self.consts['HEADERSIZE']
        sat_offset = params[self.consts['SID_SAT_IND']] * sect_size + self.consts['HEADERSIZE']

        offset = ind * 4
        
        while offset >= sect_size:
            offset = offset - sect_size
            f.seek(sat_offset + sid * 4)
            sid = struct.unpack('i', f.read(4))[0]

        f.seek(sid * sect_size + self.consts['HEADERSIZE'] + offset)
        return struct.unpack('i', f.read(4))[0]
    
    def get_stream_contents(self, ind, size, params, f):
        data = b''
        sid = ind

        miniSectSize = params[self.consts['MINI_SECT_SIZE_IND']]
        sectSize = params[self.consts['SECT_SIZE_IND']]
        SSATOffset = params[self.consts['SID_SSAT_IND']] * sectSize + self.consts['HEADERSIZE']
        SATOffset = params[self.consts['SID_SAT_IND']] * sectSize + self.consts['HEADERSIZE']

        if size < params[self.consts['MINISTREAM_CUTOFF_IND']]:
            while size > 0:
                if sid < 0:
                    print("Error: reached end of ministream before end of data")
                    break 
                f.seek(self.stream_ind_to_offset(sid, params, f))
                data += f.read(min(miniSectSize, size))
                size -= miniSectSize
                sid = self.get_next_mini_sect(sid, params, f)

        else:
            while size > 0:
                if sid < 0:
                    print("Error: reached end of stream before end of data")
                    break
                f.seek(sid * sectSize + self.consts['HEADERSIZE'])
                data += f.read(min(sectSize, size))
                size -= sectSize
                sid = self.get_next_sect(sid, params, f)

        return data

# Example usage:
#filename = "./UV_spectra/240417_EtOH_Ac_sohxlet_#1.spc"
#parser = SpcFileParser(filename)
#parser.extract_data()
#x_data, y_data = parser.get_data()
#print(x_data)
#print(y_data)
