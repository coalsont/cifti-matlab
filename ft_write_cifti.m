function ft_write_cifti(filename, source, varargin)

% FT_WRITE_CIFTI writes a source structure according to FT_DATATYPE_SOURCE to a cifti file.
%
% Use as
%   ft_write_cifti(filename, source, ...)
% where optional input arguments should come in key-value pairs and may include
%   parameter      = string, fieldname that contains the data
%   brainstructure = string, fieldname that describes the brain structures (optional)
%   parcellation   = string, fieldname that describes the parcellation (optional)
%
% The brainstructure refers to the global anatomical structure, such as CortexLeft, Thalamus, etc.
% The parcellation refers to the the detailled parcellation, such as BA1, BA2, BA3, etc.
%
% See also FT_READ_CIFTI, READ_NIFTI2_HDR, WRITE_NIFTI2_HDR

% Copyright (C) 2013-2014, Robert Oostenveld
%
% This file is part of FieldTrip, see http://www.ru.nl/neuroimaging/fieldtrip
% for the documentation and details.
%
%    FieldTrip is free software: you can redistribute it and/or modify
%    it under the terms of the GNU General Public License as published by
%    the Free Software Foundation, either version 3 of the License, or
%    (at your option) any later version.
%
%    FieldTrip is distributed in the hope that it will be useful,
%    but WITHOUT ANY WARRANTY; without even the implied warranty of
%    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%    GNU General Public License for more details.
%
%    You should have received a copy of the GNU General Public License
%    along with FieldTrip. If not, see <http://www.gnu.org/licenses/>.
%
% $Id: ft_write_cifti.m 9843 2014-09-26 08:41:17Z roboos $

brainstructure  = ft_getopt(varargin, 'brainstructure'); % the default is determined further down
parcellation    = ft_getopt(varargin, 'parcellation');   % the default is determined further down
parameter       = ft_getopt(varargin, 'parameter');
precision       = ft_getopt(varargin, 'precision', 'single');

% ensure that the external toolbox is present, this adds gifti/@xmltree
ft_hastoolbox('gifti', 1);

if isfield(source, 'brainordinate')
  % copy the geometrical description from the parcellation over in the main structure
  source = copyfields(source.brainordinate, source, fieldnames(source.brainordinate));
  source = rmfield(source, 'brainordinate');
end

if isempty(brainstructure) && isfield(source, 'brainstructure') && isfield(source, 'brainstructurelabel')
  % these fields are asumed to be present from ft_read_cifti
  brainstructure = 'brainstructure';
end

if isempty(parcellation) && isfield(source, 'parcellation') && isfield(source, 'parcellationlabel')
  % these fields are asumed to be present from ft_read_cifti
  parcellation = 'parcellation';
end

if isfield(source, 'inside') && islogical(source.inside)
  % convert into an indexed representation
  source.inside = find(source.inside(:));
end

if isfield(source, 'dim') && ~isfield(source, 'transform')
  % ensure that the volumetric description is complete
  source.transform = pos2transform(source.pos);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% get the data
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

dat = source.(parameter);
if isfield(source, [parameter 'dimord'])
  dimord = source.([parameter 'dimord']);
else
  dimord = source.dimord;
end

switch dimord
  case {'pos' 'pos_scalar'}
    % NIFTI_INTENT_CONNECTIVITY_DENSE_SCALARS
    extension   = '.dscalar.nii';
    intent_code = 3006;
    intent_name = 'ConnDenseScalar';
    dat = transpose(dat);
    dimord = 'scalar_pos';
  case 'pos_pos'
    % NIFTI_INTENT_CONNECTIVITY_DENSE
    extension = '.dconn.nii';
    intent_code = 3001;
    intent_name = 'ConnDense';
  case 'pos_time'
    % NIFTI_INTENT_CONNECTIVITY_DENSE_SERIES
    extension = '.dtseries.nii';
    intent_code = 3002;
    intent_name = 'ConnDenseSeries';
    dat = transpose(dat);
    dimord = 'time_pos';
  case 'pos_freq'
    % NIFTI_INTENT_CONNECTIVITY_DENSE_SERIES
    extension = '.dtseries.nii';
    intent_code = 3002;
    intent_name = 'ConnDenseSeries';
    dat = transpose(dat);
    dimord = 'freq_pos';
    
  case {'chan' 'chan_scalar'}
    % NIFTI_INTENT_CONNECTIVITY_PARCELLATED_SCALARS
    extension   = '.pscalar.nii';
    intent_code = 3006;
    intent_name = 'ConnParcelScalr'; % due to length constraints of the NIfTI header field, the last ?a? is removed
    dat = transpose(dat);
    dimord = 'scalar_chan';
  case 'chan_chan'
    % NIFTI_INTENT_CONNECTIVITY_PARCELLATED
    extension = '.pconn.nii';
    intent_code = 3003;
    intent_name = 'ConnParcels';
  case 'chan_time'
    % NIFTI_INTENT_CONNECTIVITY_PARCELLATED_SERIES
    extension = '.ptseries.nii';
    intent_code = 3000;
    intent_name = 'ConnParcelSries'; % due to length constraints of the NIfTI header field, the first "e" is removed
    dat = transpose(dat);
    dimord = 'time_chan';
  case 'chan_freq'
    % NIFTI_INTENT_CONNECTIVITY_PARCELLATED_SERIES
    extension = '.ptseries.nii';
    intent_code = 3000;
    intent_name = 'ConnParcelSries'; % due to length constraints of the NIfTI header field, the first "e" is removed
    dat = transpose(dat);
    dimord = 'freq_chan';
    
  otherwise
    error('unsupported dimord')
end % switch

dimtok = tokenize(dimord, '_');

[p, f] = fileparts(filename);
filename = fullfile(p, [f extension]);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% construct the XML object describing the geometry
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

tree = xmltree;
tree = set(tree, 1, 'name', 'CIFTI');
tree = attributes(tree, 'add', find(tree, 'CIFTI'), 'Version', '2');
tree = add(tree, find(tree, 'CIFTI'), 'element', 'Matrix');


% The cifti file contains one Matrix, which contains one or multiple MatrixIndicesMap, which each contain
% CIFTI_INDEX_TYPE_BRAIN_MODELS The dimension represents one or more brain models.
% CIFTI_INDEX_TYPE_PARCELS      The dimension represents a parcellation scheme.
% CIFTI_INDEX_TYPE_SERIES       The dimension represents a series of regular samples.
% CIFTI_INDEX_TYPE_SCALARS      The dimension represents named scalar maps.
% CIFTI_INDEX_TYPE_LABELS       The dimension represents named label maps.


if isfield(source, brainstructure)
  BrainStructure      = source.( brainstructure         );
  BrainStructurelabel = source.([brainstructure 'label']);
elseif isfield(source, 'pos')
  BrainStructure      = ones(1,size(source.pos,1));
  BrainStructurelabel = {'INVALID'};
end

if isfield(source, parcellation)
  Parcellation      = source.( parcellation         );
  Parcellationlabel = source.([parcellation 'label']);
elseif isfield(source, 'pos')
  Parcellation      = ones(1,size(source.pos,1));
  Parcellationlabel = {'INVALID'};
end

try, BrainStructure = BrainStructure(:); end
try, Parcellation   = Parcellation(:);   end

list1 = {
  'CIFTI_STRUCTURE_CORTEX_LEFT'
  'CIFTI_STRUCTURE_CORTEX_RIGHT'
  'CIFTI_STRUCTURE_CEREBELLUM'
  'CIFTI_STRUCTURE_ACCUMBENS_LEFT'
  'CIFTI_STRUCTURE_ACCUMBENS_RIGHT'
  'CIFTI_STRUCTURE_ALL_GREY_MATTER'
  'CIFTI_STRUCTURE_ALL_WHITE_MATTER'
  'CIFTI_STRUCTURE_AMYGDALA_LEFT'
  'CIFTI_STRUCTURE_AMYGDALA_RIGHT'
  'CIFTI_STRUCTURE_BRAIN_STEM'
  'CIFTI_STRUCTURE_CAUDATE_LEFT'
  'CIFTI_STRUCTURE_CAUDATE_RIGHT'
  'CIFTI_STRUCTURE_CEREBELLAR_WHITE_MATTER_LEFT'
  'CIFTI_STRUCTURE_CEREBELLAR_WHITE_MATTER_RIGHT'
  'CIFTI_STRUCTURE_CEREBELLUM_LEFT'
  'CIFTI_STRUCTURE_CEREBELLUM_RIGHT'
  'CIFTI_STRUCTURE_CEREBRAL_WHITE_MATTER_LEFT'
  'CIFTI_STRUCTURE_CEREBRAL_WHITE_MATTER_RIGHT'
  'CIFTI_STRUCTURE_CORTEX'
  'CIFTI_STRUCTURE_DIENCEPHALON_VENTRAL_LEFT'
  'CIFTI_STRUCTURE_DIENCEPHALON_VENTRAL_RIGHT'
  'CIFTI_STRUCTURE_HIPPOCAMPUS_LEFT'
  'CIFTI_STRUCTURE_HIPPOCAMPUS_RIGHT'
  'CIFTI_STRUCTURE_INVALID'
  'CIFTI_STRUCTURE_OTHER'
  'CIFTI_STRUCTURE_OTHER_GREY_MATTER'
  'CIFTI_STRUCTURE_OTHER_WHITE_MATTER'
  'CIFTI_STRUCTURE_PALLIDUM_LEFT'
  'CIFTI_STRUCTURE_PALLIDUM_RIGHT'
  'CIFTI_STRUCTURE_PUTAMEN_LEFT'
  'CIFTI_STRUCTURE_PUTAMEN_RIGHT'
  'CIFTI_STRUCTURE_THALAMUS_LEFT'
  'CIFTI_STRUCTURE_THALAMUS_RIGHT'
  };

list2 = {
  'CORTEX_LEFT'
  'CORTEX_RIGHT'
  'CEREBELLUM'
  'ACCUMBENS_LEFT'
  'ACCUMBENS_RIGHT'
  'ALL_GREY_MATTER'
  'ALL_WHITE_MATTER'
  'AMYGDALA_LEFT'
  'AMYGDALA_RIGHT'
  'BRAIN_STEM'
  'CAUDATE_LEFT'
  'CAUDATE_RIGHT'
  'CEREBELLAR_WHITE_MATTER_LEFT'
  'CEREBELLAR_WHITE_MATTER_RIGHT'
  'CEREBELLUM_LEFT'
  'CEREBELLUM_RIGHT'
  'CEREBRAL_WHITE_MATTER_LEFT'
  'CEREBRAL_WHITE_MATTER_RIGHT'
  'CORTEX'
  'DIENCEPHALON_VENTRAL_LEFT'
  'DIENCEPHALON_VENTRAL_RIGHT'
  'HIPPOCAMPUS_LEFT'
  'HIPPOCAMPUS_RIGHT'
  'INVALID'
  'OTHER'
  'OTHER_GREY_MATTER'
  'OTHER_WHITE_MATTER'
  'PALLIDUM_LEFT'
  'PALLIDUM_RIGHT'
  'PUTAMEN_LEFT'
  'PUTAMEN_RIGHT'
  'THALAMUS_LEFT'
  'THALAMUS_RIGHT'
  };

% replace the short name with the long name
[dum, indx1, indx2] = intersect(BrainStructurelabel, list2);
BrainStructurelabel(indx1) = list1(indx2);

if any(strcmp(dimtok, 'time'))
  % construct the MatrixIndicesMap for the time axis in the data
  % NumberOfSeriesPoints="2" SeriesExponent="0" SeriesStart="0.0000000000" SeriesStep="1.0000000000" SeriesUnit="SECOND"
  tree = add(tree, find(tree, 'CIFTI/Matrix'), 'element', 'MatrixIndicesMap');
  branch = find(tree, 'CIFTI/Matrix/MatrixIndicesMap');
  branch = branch(end);
  tree = attributes(tree, 'add', branch, 'AppliesToMatrixDimension', printwithcomma(find(strcmp(dimtok, 'time'))-1));
  tree = attributes(tree, 'add', branch, 'IndicesMapToDataType', 'CIFTI_INDEX_TYPE_SERIES');
  tree = attributes(tree, 'add', branch, 'NumberOfSeriesPoints', num2str(length(source.time)));
  tree = attributes(tree, 'add', branch, 'SeriesExponent', num2str(0));
  tree = attributes(tree, 'add', branch, 'SeriesStart', num2str(source.time(1)));
  tree = attributes(tree, 'add', branch, 'SeriesStep', num2str(median(diff(source.time))));
  tree = attributes(tree, 'add', branch, 'SeriesUnit', 'SECOND');
end % if time

if any(strcmp(dimtok, 'freq'))
  % construct the MatrixIndicesMap for the frequency axis in the data
  % NumberOfSeriesPoints="2" SeriesExponent="0" SeriesStart="0.0000000000" SeriesStep="1.0000000000" SeriesUnit="HZ"
  tree = add(tree, find(tree, 'CIFTI/Matrix'), 'element', 'MatrixIndicesMap');
  branch = find(tree, 'CIFTI/Matrix/MatrixIndicesMap');
  branch = branch(end);
  tree = attributes(tree, 'add', branch, 'AppliesToMatrixDimension', printwithcomma(find(strcmp(dimtok, 'freq'))-1));
  tree = attributes(tree, 'add', branch, 'IndicesMapToDataType', 'CIFTI_INDEX_TYPE_SCALARS');
  tree = attributes(tree, 'add', branch, 'NumberOfSeriesPoints', num2str(length(source.freq)));
  tree = attributes(tree, 'add', branch, 'SeriesExponent', num2str(0));
  tree = attributes(tree, 'add', branch, 'SeriesStart', num2str(source.freq(1)));
  tree = attributes(tree, 'add', branch, 'SeriesStep', num2str(median(diff(source.freq)))); % this requires even sampling
  tree = attributes(tree, 'add', branch, 'SeriesUnit', 'HZ');
end % if freq

if any(strcmp(dimtok, 'scalar'))
  tree = add(tree, find(tree, 'CIFTI/Matrix'), 'element', 'MatrixIndicesMap');
  branch = find(tree, 'CIFTI/Matrix/MatrixIndicesMap');
  branch = branch(end);
  tree = attributes(tree, 'add', branch, 'AppliesToMatrixDimension', printwithcomma(find(strcmp(dimtok, 'scalar'))-1));
  tree = attributes(tree, 'add', branch, 'IndicesMapToDataType', 'CIFTI_INDEX_TYPE_SCALARS');
  tree = add(tree, branch, 'element', 'NamedMap');
  branch = find(tree, 'CIFTI/Matrix/MatrixIndicesMap/NamedMap');
  branch = branch(end);
  [tree, uid] = add(tree, branch, 'element', 'MapName');
  tree        = add(tree, uid, 'chardata', parameter);
end % if not freq and time

if any(strcmp(dimtok, 'pos'))
  % construct the MatrixIndicesMap for the geometry
  tree = add(tree, find(tree, 'CIFTI/Matrix'), 'element', 'MatrixIndicesMap');
  branch = find(tree, 'CIFTI/Matrix/MatrixIndicesMap');
  branch = branch(end);
  tree = attributes(tree, 'add', branch, 'AppliesToMatrixDimension', printwithcomma(find(strcmp(dimtok, 'pos'))-1));
  tree = attributes(tree, 'add', branch, 'IndicesMapToDataType', 'CIFTI_INDEX_TYPE_BRAIN_MODELS');
  
  if isfield(source, 'dim')
    switch source.unit
      case 'mm'
        MeterExponent = -3;
      case 'cm'
        MeterExponent = -2;
      case 'dm'
        MeterExponent = -1;
      case 'm'
        MeterExponent = 0;
      otherwise
        error('unsupported source.unit')
    end % case
    
    [tree, uid] = add(tree, branch, 'element', 'Volume');
    tree        = attributes(tree, 'add', uid, 'VolumeDimensions', printwithcomma(source.dim));
    [tree, uid] = add(tree, uid, 'element', 'TransformationMatrixVoxelIndicesIJKtoXYZ');
    tree        = attributes(tree, 'add', uid, 'MeterExponent', num2str(MeterExponent));
    tree        = add(tree, uid, 'chardata', printwithspace(source.transform')); % it needs to be transposed

    [X, Y, Z] = ndgrid(1:source.dim(1), 1:source.dim(2), 1:source.dim(3));
    xyz = ft_warp_apply(source.transform, [X(:) Y(:) Z(:)]);
    isvolume = isequal(size(source.pos), size(xyz)) && all(sum((source.pos - xyz).^2,2)./sum((source.pos + xyz).^2,2)<eps);
  else
    isvolume = false;
  end
  
  for i=1:length(BrainStructurelabel)
    % write one brainstructure for each group of vertices
    if isempty(regexp(BrainStructurelabel{i}, '^CIFTI_STRUCTURE_', 'once'))
      BrainStructurelabel{i} = ['CIFTI_STRUCTURE_' BrainStructurelabel{i}];
    end
    
    sel = (BrainStructure==i);
    IndexCount = sum(sel);
    IndexOffset = find(sel, 1, 'first') - 1; % zero offset
    
    branch = find(tree, 'CIFTI/Matrix/MatrixIndicesMap');
    branch = branch(end);
    tree = add(tree, branch, 'element', 'BrainModel');
    branch = find(tree, 'CIFTI/Matrix/MatrixIndicesMap/BrainModel');
    branch = branch(end);
    
    if isvolume
      tree = attributes(tree, 'add', branch, 'IndexOffset', printwithspace(IndexOffset));
      tree = attributes(tree, 'add', branch, 'IndexCount', printwithspace(IndexCount));
      tree = attributes(tree, 'add', branch, 'ModelType', 'CIFTI_MODEL_TYPE_VOXELS');
      tree = attributes(tree, 'add', branch, 'BrainStructure', BrainStructurelabel{i});
      tree = add(tree, branch, 'element', 'VoxelIndicesIJK');
      branch = find(tree, 'CIFTI/Matrix/MatrixIndicesMap/BrainModel/VoxelIndicesIJK');
      branch = branch(end);
      tmp = source.pos(sel,:);
      tmp = ft_warp_apply(inv(source.transform), tmp);
      tmp = round(tmp)' - 1; % zero offset
      tree = add(tree, branch, 'chardata', printwithspace(tmp));
    else
      tmp = find(sel)-IndexOffset-1; % zero offset
      tree = attributes(tree, 'add', branch, 'IndexOffset', printwithspace(IndexOffset));
      tree = attributes(tree, 'add', branch, 'IndexCount', printwithspace(IndexCount));
      tree = attributes(tree, 'add', branch, 'ModelType', 'CIFTI_MODEL_TYPE_SURFACE');
      tree = attributes(tree, 'add', branch, 'BrainStructure', BrainStructurelabel{i});
      tree = attributes(tree, 'add', branch, 'SurfaceNumberOfVertices', printwithspace(IndexCount));
      tree = add(tree, branch, 'element', 'VertexIndices');
      branch = find(tree, 'CIFTI/Matrix/MatrixIndicesMap/BrainModel/VertexIndices');
      branch = branch(end);
      tree = add(tree, branch, 'chardata', printwithspace(tmp));
    end
    
  end % for each BrainStructurelabel
  
end % if pos

if any(strcmp(dimtok, 'chan'))
  tree = add(tree, find(tree, 'CIFTI/Matrix'), 'element', 'MatrixIndicesMap');
  branch = find(tree, 'CIFTI/Matrix/MatrixIndicesMap');
  branch = branch(end);
  tree = attributes(tree, 'add', branch, 'AppliesToMatrixDimension', printwithcomma(find(strcmp(dimtok, 'chan'))-1));
  tree = attributes(tree, 'add', branch, 'IndicesMapToDataType', 'CIFTI_INDEX_TYPE_PARCELS');
  
  if isfield(source, 'dim')
    switch source.unit
      case 'mm'
        MeterExponent = -3;
      case 'cm'
        MeterExponent = -2;
      case 'dm'
        MeterExponent = -1;
      case 'm'
        MeterExponent = 0;
      otherwise
        error('unsupported source.unit')
    end % case
    
    [tree, uid] = add(tree, branch, 'element', 'Volume');
    tree        = attributes(tree, 'add', uid, 'VolumeDimensions', printwithcomma(source.dim));
    [tree, uid] = add(tree, uid, 'element', 'TransformationMatrixVoxelIndicesIJKtoXYZ');
    tree        = attributes(tree, 'add', uid, 'MeterExponent', num2str(MeterExponent));
    tree        = add(tree, uid, 'chardata', printwithspace(source.transform')); % it needs to be transposed
  end
  
  if isfield(source, 'tri')
    
    % add the surfaces
    for i=1:length(BrainStructurelabel)
      sel = find(BrainStructure~=i);
      [mesh.pnt, mesh.tri] = remove_vertices(source.pos, source.tri, sel);
      mesh.unit = source.unit;
      
      if isempty(mesh.pnt) || isempty(mesh.tri)
        continue;
      end
      
      [tree, uid] = add(tree, branch, 'element', 'Surface');
      tree        = attributes(tree, 'add', uid, 'BrainStructure', BrainStructurelabel{i});
      tree        = attributes(tree, 'add', uid, 'SurfaceNumberOfVertices', printwithspace(size(mesh.pnt,1)));
    end
    
  end % if isfield tri
  
  parcel = source.label; % channels are used to represent parcels
  for i=1:numel(parcel)
    indx = find(strcmp(Parcellationlabel, parcel{i}));
    if isempty(indx)
      continue
    end
    selParcel = (Parcellation==indx);
    structure = BrainStructurelabel(unique(BrainStructure(selParcel)));
    
    branch = find(tree, 'CIFTI/Matrix/MatrixIndicesMap');
    branch = branch(end);
    
    tree = add(tree, branch, 'element', 'Parcel');
    branch = find(tree, 'CIFTI/Matrix/MatrixIndicesMap/Parcel');
    branch = branch(end);
    tree = attributes(tree, 'add', branch, 'Name', parcel{i});
    
    for j=1:length(structure)
      selStructure = (BrainStructure==find(strcmp(BrainStructurelabel, structure{j})));
      indx   = find(selParcel & selStructure);
      offset = find(selStructure, 1, 'first') - 1;
      
      fprintf('parcel %s contains %d vertices in %s\n', parcel{i}, length(indx), structure{j});
      
      branch = find(tree, 'CIFTI/Matrix/MatrixIndicesMap/Parcel');
      branch = branch(end);
      
      if any(strcmp({'CIFTI_STRUCTURE_CORTEX_LEFT', 'CIFTI_STRUCTURE_CORTEX_RIGHT'}, structure{j}))
        tree = add(tree, branch, 'element', 'Vertices');
        branch = find(tree, 'CIFTI/Matrix/MatrixIndicesMap/Parcel/Vertices');
        branch = branch(end);
        tree = attributes(tree, 'add', branch, 'BrainStructure', structure{j});
        tmp  = indx - offset - 1;
        tree = add(tree, branch, 'chardata', printwithspace(tmp));
        
      else
        tree = add(tree, branch, 'element', 'VoxelIndicesIJK');
        branch = find(tree, 'CIFTI/Matrix/MatrixIndicesMap/Parcel/VoxelIndicesIJK');
        branch = branch(end);
        tmp = ft_warp_apply(inv(source.transform), source.pos(indx,:));
        tmp = round(tmp)' - 1; % zero offset
        tree = add(tree, branch, 'chardata', printwithspace(tmp));
      end

    end % for each structure spanned by this parcel
  end % for each parcel
end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% write everything to file
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% 540 bytes with nifti-2 header
% 4 bytes that indicate the presence of a header extension [1 0 0 0]
% 4 bytes with the size of the header extension in big endian?
% 4 bytes with the header extension code NIFTI_ECODE_CIFTI [0 0 0 32]
% variable number of bytes with the xml section, at the end there might be some empty "junk"
% 8 bytes, presumaby with the size and type?
% variable number of bytes with the voxel data

xmlfile = [tempname '.xml'];  % this will contain the cifti XML structure
save(tree, xmlfile);          % write the XMLTREE object to disk

xmlfid = fopen(xmlfile, 'rb');
xmldat = fread(xmlfid, [1, inf], 'char');
fclose(xmlfid);

% we do not want the content of the XML elements to be nicely formatted, as it might create confusion when reading
% therefore detect and remove whitespace immediately following a ">" and preceding a "<"
whitespace = false(size(xmldat));

gt = int8('>');
lt = int8('<');
ws = int8(sprintf(' \t\r\n'));

b = find(xmldat==gt);
e = find(xmldat==lt);
b = b(1:end-1); % the XML section ends with ">", this is not of relevance
e = e(2:end);   % the XML section starts with "<", this is not of relevance
b = b+1;
e = e-1;

for i=1:length(b)
  for j=b(i):1:e(i)
    if any(ws==xmldat(j))
      whitespace(j) = true;
    else
      break
    end
  end
end

for i=1:length(b)
  for j=e(i):-1:b(i)
    if any(ws==xmldat(j))
      whitespace(j) = true;
    else
      break
    end
  end
end

% keep it if there is _only_ whitespace between the  ">" and "<"
for i=1:length(b)
  if all(whitespace(b(i):e(i)))
    whitespace(b(i):e(i)) = false;
  end
end

% remove the padding whitespace
xmldat = xmldat(~whitespace);

xmlsize = length(xmldat);
xmlpad  = ceil((xmlsize+8)/16)*16 - (xmlsize+8);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% construct the NIFTI-2 header
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

hdr.magic = [110 43 50 0 13 10 26 10];

% see http://nifti.nimh.nih.gov/nifti-1/documentation/nifti1fields/nifti1fields_pages/datatype.html
switch precision
  case 'uint8'
    hdr.datatype = 2;
  case 'int16'
    hdr.datatype = 4;
  case 'int32'
    hdr.datatype = 8;
  case 'single'
    hdr.datatype = 16;
  case 'double'
    hdr.datatype = 64;
  case 'int8'
    hdr.datatype = 256;
  case 'uint16'
    hdr.datatype = 512;
  case 'uint32'
    hdr.datatype = 768;
  case 'uint64'
    hdr.datatype = 1280;
  case 'int64'
    hdr.datatype = 1024;
  otherwise
    error('unsupported precision "%s"', precision);
end

switch precision
  case {'uint8' 'int8'}
    hdr.bitpix = 1*8;
  case {'uint16' 'int16'}
    hdr.bitpix = 2*8;
  case {'uint32' 'int32'}
    hdr.bitpix = 4*8;
  case {'uint64' 'int64'}
    hdr.bitpix = 8*8;
  case 'single'
    hdr.bitpix = 4*8;
  case 'double'
    hdr.bitpix = 8*8;
  otherwise
    error('unsupported precision "%s"', precision);
end

% dim(1) represents the number of dimensions
% for a normal nifti file, dim(2:4) are x, y, z, dim(5) is time, dim(6:8) are free to choose
switch dimord
  case 'pos_scalar'
    hdr.dim             = [6 1 1 1 1 size(source.pos,1) 1 1]; % only single scalar
  case 'scalar_pos'
    hdr.dim             = [6 1 1 1 1 1 size(source.pos,1) 1]; % only single scalar
  case 'chan_scalar'
    hdr.dim             = [6 1 1 1 1 numel(source.label) 1 1]; % only single scalar
  case 'scalar_chan'
    hdr.dim             = [6 1 1 1 1 1 numel(source.label) 1]; % only single scalar
  case 'pos_time'
    hdr.dim             = [6 1 1 1 1 size(source.pos,1) length(source.time) 1];
  case 'time_pos'
    hdr.dim             = [6 1 1 1 1 length(source.time) size(source.pos,1) 1];
  case 'chan_time'
    hdr.dim             = [6 1 1 1 1 length(source.label) length(source.time) 1];
  case 'time_chan'
    hdr.dim             = [6 1 1 1 1 length(source.time) length(source.label) 1];
  case 'pos_pos'
    hdr.dim             = [6 1 1 1 1 size(source.pos,1) size(source.pos,1)  1];
  case 'chan_chan'
    hdr.dim             = [6 1 1 1 1 length(source.label) length(source.label) 1];
    %   case 'chan_chan_time'
    %     hdr.dim             = [6 1 1 1 1 length(source.label) length(source.label) length(source.time)];
    %   case 'pos_pos_time'
    %     hdr.dim             = [6 1 1 1 1 size(source.pos,1)  size(source.pos,1)  length(source.time)];
    %   case 'chan_chan_freq'
    %     hdr.dim             = [6 1 1 1 1 length(source.label) length(source.label) length(source.freq)];
    %   case 'pos_pos_freq'
    %     hdr.dim             = [6 1 1 1 1 size(source.pos,1)  size(source.pos,1)  length(source.freq)];
  otherwise
    error('unsupported dimord "%s"', dimord)
end % switch

hdr.intent_p1       = 0;
hdr.intent_p2       = 0;
hdr.intent_p3       = 0;
hdr.pixdim          = [0 1 1 1 1 1 1 1];
hdr.vox_offset      = 4+540+8+xmlsize+xmlpad;
hdr.scl_slope       = 1; % WorkBench sets scl_slope/scl_inter to 1 and 0, although 0 and 0 would also be fine - both mean the same thing according to the nifti spec
hdr.scl_inter       = 0;
hdr.cal_max         = 0;
hdr.cal_min         = 0;
hdr.slice_duration  = 0;
hdr.toffset         = 0;
hdr.slice_start     = 0;
hdr.slice_end       = 0;
hdr.descrip         = char(zeros(1,80));
hdr.aux_file        = char(zeros(1,24));
hdr.qform_code      = 0;
hdr.sform_code      = 0;
hdr.quatern_b       = 0;
hdr.quatern_c       = 0;
hdr.quatern_d       = 0;
hdr.qoffset_x       = 0;
hdr.qoffset_y       = 0;
hdr.qOffset_z       = 0;
hdr.srow_x          = [0 0 0 0];
hdr.srow_y          = [0 0 0 0];
hdr.srow_z          = [0 0 0 0];
hdr.slice_code      = 0;
hdr.xyzt_units      = 0;
hdr.intent_code     = intent_code;
hdr.intent_name     = cat(2, intent_name, zeros(1, 16-length(intent_name))); % zero-pad up to 16 characters
hdr.dim_info        = 0;
hdr.unused_str      = char(zeros(1,15));

% open the file
fid = fopen(filename, 'wb');

% write the header, this is 4+540 bytes
write_nifti2_hdr(fid, hdr);

% write the xml section to a temporary file
xmlfile = 'debug.xml';
tmp = fopen(xmlfile, 'w');
fwrite(tmp, xmldat, 'char');
fclose(tmp);

% write the cifti header extension
fwrite(fid, [1 0 0 0], 'uint8');
fwrite(fid, 8+xmlsize+xmlpad, 'int32');   % esize
fwrite(fid, 32, 'int32');                 % etype
fwrite(fid, xmldat, 'char');              % write the ascii XML section
fwrite(fid, zeros(1,xmlpad), 'uint8');    % zero-pad to the next 16 byte boundary

fwrite(fid, dat, precision);

fclose(fid);

% write the surface information to one or multiple accompanying gifti files
if isfield(source, 'tri')
    
  if isfield(source, brainstructure)
    % it contains information about anatomical structures, including cortical surfaces
    for i=1:length(BrainStructurelabel)
      sel = find(BrainStructure~=i);
      [mesh.pnt, mesh.tri] = remove_vertices(source.pos, source.tri, sel);
      mesh.unit = source.unit;
      
      if isempty(mesh.pnt) || isempty(mesh.tri)
        continue;
      end
      
      if ~isempty(regexp(BrainStructurelabel{i}, '^CIFTI_STRUCTURE_', 'once'))
        BrainStructurelabel{i} = BrainStructurelabel{i}(17:end);
      end
      
      [p, f, x] = fileparts(filename);
      filetok = tokenize(f, '.');
      surffile = fullfile(p, [filetok{1} '.' BrainStructurelabel{i} '.surf.gii']);
      ft_write_headshape(surffile, mesh, 'format', 'gifti');
    end
    
  else
    mesh.pnt = source.pos;
    mesh.tri = source.tri;
    mesh.unit = source.unit;
    
    [p, f, x] = fileparts(filename);
    filetok = tokenize(f, '.');
    surffile = fullfile(p, [filetok{1} '.surf.gii']);
    ft_write_headshape(surffile, mesh, 'format', 'gifti');
  end
  
end % if isfield tri


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% SUBFUNCTION to print lists of numbers with appropriate whitespace
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function s = printwithspace(x)
x = x(:)'; % convert to vector
if all(round(x)==x)
  % print as integer value
  s = sprintf('%d ', x);
else
  % print as floating point value
  s = sprintf('%f ', x);
end
s = s(1:end-1);

function s = printwithcomma(x)
x = x(:)'; % convert to vector
if all(round(x)==x)
  % print as integer value
  s = sprintf('%d,', x);
else
  % print as floating point value
  s = sprintf('%f,', x);
end
s = s(1:end-1);


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% SUBFUNCTION from roboos/matlab/triangle
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function [pntR, triR] = remove_vertices(pnt, tri, removepnt)

npnt = size(pnt,1);
ntri = size(tri,1);

if all(removepnt==0 | removepnt==1)
  removepnt = find(removepnt);
end

% remove the vertices and determine the new numbering (indices) in numb
keeppnt = setdiff(1:npnt, removepnt);
numb    = zeros(1,npnt);
numb(keeppnt) = 1:length(keeppnt);

% look for triangles referring to removed vertices
removetri = false(ntri,1);
removetri(ismember(tri(:,1), removepnt)) = true;
removetri(ismember(tri(:,2), removepnt)) = true;
removetri(ismember(tri(:,3), removepnt)) = true;

% remove the vertices and triangles
pntR = pnt(keeppnt, :);
triR = tri(~removetri,:);

% renumber the vertex indices for the triangles
triR = numb(triR);
