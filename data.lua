require 'torch'
require 'torchx'
require 'image'
require 'xlua'
local gm = require 'graphicsmagick'

data_path = "../data"
--data_path = "../data/test"
image_size = 64
validRatio = 0.1
testRatio  = 0.1
data_cache = true
local imgNetPreproc = true
local mean = { 0.485, 0.456, 0.406 }
local std = { 0.229, 0.224, 0.225 }

local function preprocessImage(img)
    local size = math.min(img:size(2), img:size(3))
    return image.scale(image.crop(img, "c", size, size), image_size,
        image_size)
end

local function imgNetNorm(dataTensor) 
    for i=1, dataTensor:size(1) do
        for j=1, 3 do
            dataTensor[i][j]:add(mean[j]):div(std[j])
        end   
    end
end

local function imageLoad(img_path)
    return gm.Image(img_path):toTensor('float', 'RGB', 'DHW')
end

--local normalization = require 'preprocess'

local function getData(data_path) 
    local tiles = paths.indexdir(paths.concat(data_path, "tiles"), {"tif"}) 
    local masks = paths.indexdir(paths.concat(data_path, "masks"), {"tif"})
    local size = tiles:size()
    local shuffle = torch.randperm(size) -- shuffle the data
    local input  = torch.FloatTensor(size, 3, image_size, image_size)
    local target = torch.FloatTensor(size, 2, image_size, image_size)

    for i=1,tiles:size() do
        local img = preprocessImage(imageLoad(tiles:filename(i)))
        local idx = shuffle[i]
        input[idx]:copy(img)
        xlua.progress(i, size)
        collectgarbage()
    end

    for i=1,masks:size() do
        local img = preprocessImage(imageLoad(masks:filename(i)))
        local idx = shuffle[i]
        local tmp = torch.FloatTensor(image_size, image_size)
        tmp:copy(img[3]:apply(function(x)
                                       if x > 0 then
                                           return 1
                                        end
                                      end))
        target[idx][2]:copy(tmp:apply(function(x)
                                          if x > 0 then
                                             return 0
                                          else 
                                             return 1
                                          end
                                      end))
        xlua.progress(i, size)
        collectgarbage()
    end
-- train, validation, test split
    local nValid = math.floor(size * validRatio)
    local nTest  = math.floor(size * testRatio)
    local nTrain = size - nValid - nTest
    print("Train size: " .. nTrain)
    print("Validaton size: " .. nValid)
    print("Test size: " .. nTest)

    print("Before norm: " .. input[1][1][1][1])

    imgNetNorm(input) 

    print("after afte: " .. input[1][1][1][1])

    local trainInput  = input:narrow (1, 1, nTrain)
    local trainTarget = target:narrow(1, 1, nTrain)
    local validInput  = input:narrow (1, nTrain+1, nValid)
    local validTarget = target:narrow(1, nTrain+1, nValid)
    local testInput   = input:narrow (1, nTrain+nValid+1, nTest)
    local testTarget   = target:narrow(1, nTrain+nValid+1, nTest)

    trainData = {data = trainInput, labels = trainTarget}
    testData = {data = testInput, labels = testTarget}
    validData = {data = validInput, labels = validTarget}

    --normalization(trainData, validData)   

    torch.save(paths.concat(opt.save,'train.t7'), trainData)
    torch.save(paths.concat(opt.save,'test.t7'), testData)
    torch.save(paths.concat(opt.save,'valid.t7'), validData)
    return  trainData, validData
end

if data_cache then
   trainData = torch.load(paths.concat(opt.save,'train.t7'))
   validData = torch.load(paths.concat(opt.save,'valid.t7'))
else 
   trainData, validData = getData(data_path)
end



trainData.size = function() return trainData.data:size(1) end
validData.size = function() return validData.data:size(1) end

print(trainData)
print(validData)
print("Done")

return {
   trainData = trainData,
   validData = validData
}
