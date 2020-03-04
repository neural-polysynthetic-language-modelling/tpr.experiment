#!/usr/bin/env ducttape

# Define global variables
global {
       JSALT_NPLM_data="/home/lanes/JSALT_NPLM_data"
       python37="/usr/bin/python3.7"
}

# Clone the finite-state analyzer and compile it
task fst
  :: url="git@github.com:SaintLawrenceIslandYupik/finite_state_morphology.git"
   > analyzer="fst/lexicon/lexicon.py"
   > extract_splits="fst/lexicon/extract-split-words.py"
   > extract_analyses="fst/lexicon/extract-analyzed-words.py"
   > lexc="fst/ess.lexc"
   > s2u="fst/ess.fomabin"             # Surface form to underlying form analyzer
   > i2u="fst/ess.underlying.fomabin"  # Intermediate form to underlying form analyzer
{
	git clone --depth 1 --single-branch --branch jsalt2019 ${url} fst
	cd fst
	make ess.fomabin ess.underlying.fomabin
}

# Clone sentence-splitting code
task europarl_tools
  :: url="git@github.com:dowobeha/europarl_tools.git"
   > tokenizer="tools/tools/tokenizer.perl"
   > split_sentences="tools/tools/split-sentences.perl"
{
	git clone --depth 1 --single-branch --branch master ${url} tools
}

# Gather data into train, dev, and test splits
task data
  :: data=$JSALT_NPLM_data
  :: lang=(Lang: ess)
  :: condition=(Condition: all nt tiny)
   > train
   > dev
   > test
{

	if [[ "${lang}" == "ess" ]]; then

	   find ${data}/Inuit-Yupik/ess/monolingual_corpus/new_testament/new.testament.ess/ -maxdepth 1 -type f | sort | grep 'B03_.*_Luke' | xargs cat | sed 's,^[[:digit:]]\+[[:space:]]\+,,' | grep -v '^ *$' > ${dev}

	   find ${data}/Inuit-Yupik/ess/monolingual_corpus/new_testament/new.testament.ess/ -maxdepth 1 -type f | sort | grep 'B04_.*_John' | xargs cat | sed 's,^[[:digit:]]\+[[:space:]]\+,,' | grep -v '^ *$' > ${test}

	   if [[ "${condition}" == "nt" || "${condition}" == "all" ]]; then

	      find ${data}/Inuit-Yupik/ess/monolingual_corpus/new_testament/new.testament.ess/ -maxdepth 1 -type f | sort | grep -v 'B03_.*_Luke' | grep -v 'B04_.*_John' | xargs cat | sed 's,^[[:digit:]]\+[[:space:]]\+,,' | grep -v '^ *$' > ${train}

	   fi

	   if [[ "${condition}" == "all" ]]; then
	   
	     for dir in elementary_primers/level1.kallagneghet-drumbeats    \
	                elementary_primers/level2.akiingqwaghneghet-echoes  \
			elementary_primers/level3.suluwet-whisperings nagai \
			sivuqam_nangaghnegha/sivuqam_volume1                \
			sivuqam_nangaghnegha/sivuqam_volume2                \
			sivuqam_nangaghnegha/sivuqam_volume3                \
			ungipaghaghlanga; do

		cat ${data}/Inuit-Yupik/ess/monolingual_corpus/${dir}/*.gold.ess/*.ess.txt >> ${train}	     

	     done

	   fi

	   if [[ "${condition}" == "tiny" ]]; then

	     for dir in elementary_primers/level1.kallagneghet-drumbeats ; do

		cat ${data}/Inuit-Yupik/ess/monolingual_corpus/${dir}/*.gold.ess/*.ess.txt | head -n 10 >> ${train}	     

	     done	   

	   fi

	fi
}

# Perform sentence splitting
task split_sentences
   < script=$split_sentences@europarl_tools
   < raw_train=$train@data
   < raw_dev=$dev@data
   < raw_test=$test@data
  :: lang=(Lang: ess)
   > train
   > dev
   > test
{
	${script} -l ${lang} < ${raw_train} | grep -v '<P>' > ${train}
	${script} -l ${lang} < ${raw_dev}   | grep -v '<P>' > ${dev}
	${script} -l ${lang} < ${raw_test}  | grep -v '<P>' > ${test}
}

# Take Yupik sentences and tokenize into words
task tokenize
   < script=$tokenizer@europarl_tools
   < train_in=$train@split_sentences
   < dev_in=$dev@split_sentences
   < test_in=$test@split_sentences
  :: lang=(Lang: ess)
   > train
   > dev
   > test
{
	${script} -l ${lang} < ${train_in} > ${train}
	${script} -l ${lang} < ${dev_in}   > ${dev}
	${script} -l ${lang} < ${test_in}  > ${test}
}

# Run finite-state analyzer over Yupik words (outputs 3 forms per word)
task analyze
  < python37=@
  < analyzer=@fst
  < in=(Split: train=@tokenize dev=@tokenize test=@tokenize)
  < s2u=@fst
  < i2u=@fst
  < lexc=@fst
  > out
{
	${python37} ${analyzer} --mode   t2a     \
	                        --corpus ${in}   \
				--lexc   ${lexc} \
				--s2u    ${s2u}  \
				--i2u    ${i2u}  \
				--output ${out}
}

# For each analyzer Yupik word, extract the part of the analysis that we care about
task split_words
   < python37=@
   < extract_splits=@fst
   < in=$out@analyze
   > out
{
	${python37} ${extract_splits} < ${in} > ${out}
}

# Set up a Python3.7 virtual environment and install dependencies using pip3
task venv
   < python37=@
  :: url="git@github.com:neural-polysynthetic-language-modelling/tpr.git"
   > activate="bin/activate"
{
	git clone --depth 1 --single-branch --branch master ${url} code
	mv code/requirements.txt .
	${python37} -m venv .
	source ${activate}
	pip3 install -r requirements.txt
}

# Clone the TPR repo
task tpr
   < python37=@
  :: url="git@github.com:neural-polysynthetic-language-modelling/tpr.git"
   > create_alphabet="code/features.py"
   > seq2seq="code/seq2seq.py"
   > corpus="code/corpus.py"
   > tokenizer="code/tokenizer.py"
   > ess_alphabet_tsv="code/ess.vocab.tsv"
   > autoencoder="code/autoencoder.py"
{
	git clone --depth 1 --single-branch --branch master ${url} code
}

# Create the alphabet
task alphabet
   < activate=@venv
   < create_alphabet=@tpr
   < in=(Lang: ess=$ess_alphabet_tsv@tpr)
   > out
   > log
{
	source ${activate}
	python3 ${create_alphabet} ${in} ${out} &> ${log}
}

# Create and pickle Yupik tokenizer object
task tokenizer
   < activate=@venv
   < tokenizer=@tpr
  :: language=(Lang: ess)
  :: delimiter=(Lang: ess='^')
  :: use_nltk=(Lang: ess=False)
   > out
   > log
{
	source ${activate}
	python3 ${tokenizer} --language ${language}            \
	                     --morpheme_delimiter ${delimiter} \
			     --use_nltk_tokenizer ${use_nltk}  \
			     --output_file ${out}              \
			     &> ${log}
}

# Create a dictionary of Yupik morphemes, then pickle it
task morphemes
   < activate=@venv
   < script=$corpus@tpr
   < tokenizer=$out@tokenizer
   < alphabet=$out@alphabet
  :: blacklist_char=(Lang: ess='*')
  :: max_characters=(Lang: ess=22)
  :: start_of_morpheme=(Lang: ess='<morpheme>')
  :: end_of_morpheme=(Lang: ess='</morpheme>')  
#   < in=(Lang: ess=$out@split_words[Condition:all,Split:train])
   < in=(Lang: ess=$out@split_words[Condition:tiny,Split:train])
   > out
   > log
{
	source ${activate}
	python3 ${script} --alphabet             ${alphabet}           \
	                  --tokenizer            ${tokenizer}          \
			  --blacklist_character "${blacklist_char}"    \
			  --max_characters       ${max_characters}     \
			  --start_of_morpheme   "${start_of_morpheme}" \
			  --end_of_morpheme     "${end_of_morpheme}"   \
			  --input_file           ${in}                 \
			  --output_file          ${out}                \
			  &> ${log}
}

# Train an autoencoder using the dictionary of Yupik morphemes
#
# For each Yupik morpheme, this calculates a gold-standard TPR,
# then uses that as the input to the autoencoder,
# and also uses it as the correct answer.
#
# This uses Unbinding Loss.
#
task morpheme_vectors
   < activate=@venv
   < script=$autoencoder@tpr
   < corpus=$out@morphemes
  :: hidden_size=(MV_Hidden: 64 128 256)
  :: hidden_layers=(MV_Layers: 1 2 3)
  :: batch_size=(MV_Batch: 1000 2000 4000 8000)
  :: num_epochs=(MV_Epochs: 100 1000 5000 10000)
  :: print_every=50
  :: learning_rate=(MV_LR: 0.01 0.1)
   > out
   > log
{
	source ${activate}
	python3 ${script} --corpus               ${corpus}             \
	                  --hidden_size          ${hidden_size}        \
			  --hidden_layers        ${hidden_layers}      \
                          --batch_size           ${batch_size}         \
                          --num_epochs           ${num_epochs}         \
			  --print_every          ${print_every}        \
                          --learning_rate        ${learning_rate}      \
			  --output_file          ${out}                \
			  &> ${log}

}

# Run autoencoder
task eval_morpheme_vectors
   < activate=@venv
   < script=$autoencoder@tpr
   < model=$out@morpheme_vectors
  :: batch_size=8000
   > out
   > log
{
	source ${activate}
	python3 ${script} --morpheme_vectors     ${model}              \
                          --batch_size           ${batch_size}         \
                           > ${out}                                    \
			  2> ${log}

}


plan {
     reach eval_morpheme_vectors via (MV_Hidden: 128) * (MV_Batch: 2000) * (MV_Epochs: 100) * (MV_Layers: 1) * (MV_LR: 0.01) * (Lang: ess) * (Condition: tiny) 

#     reach split_words via (Lang: ess) * (Condition: all) * (Split: train dev)
     
}
