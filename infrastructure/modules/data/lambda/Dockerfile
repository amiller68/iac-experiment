FROM public.ecr.aws/lambda/nodejs:18

COPY package.json ./
RUN npm install --production
COPY index.js ./ 